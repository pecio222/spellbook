{{ config(
    schema = 'magiceden_polygon',
    alias = alias('events'),
    tags = ['dunesql'],
    materialized = 'incremental',
    file_format = 'delta',
    incremental_strategy = 'merge',
    unique_key = ['block_date', 'unique_trade_id']
    )
}}

{% set nft_start_date = "TIMESTAMP '2022-03-16'" %}
{% set magic_eden_nonce = '10013141590000000000000000000000000000' %}
{% set fee_address_1 = '0xca9337244b5f04cb946391bc8b8a980e988f9a6a' %}
{% set fee_address_2 = '0x1eca4dd8ecb97b45054c81438f6f49d18ce4f343' %}
{% set zeroex_proxy = '0xdef1c0ded9bec7f1a1670819833240f027b25eff' %}


WITH erc721_trades AS (
    SELECT CASE when direction = 0 THEN 'buy' ELSE 'sell' END AS trade_category,
          evt_block_time,
          evt_block_number,
          evt_tx_hash,
          contract_address,
          evt_index,
          'Trade' AS evt_type,
          CASE when direction = 0 THEN taker ELSE maker END AS buyer,
          CASE when direction = 0 THEN maker ELSE taker END AS seller,
          erc721Token AS nft_contract_address,
          erc721TokenId AS token_id,
          cast(1 as uint256) AS number_of_items,
          'erc721' AS token_standard,
          CASE
               WHEN erc20Token in (0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee, 0x0000000000000000000000000000000000001010)
               THEN 0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270
               ELSE erc20Token
          END AS currency_contract,
          erc20TokenAmount AS fill_amount_raw,
          erc20Token as original_erc20_token
    FROM {{ source ('zeroex_polygon', 'ExchangeProxy_evt_ERC721OrderFilled') }}
    WHERE starts_with(cast(nonce as varchar),'{{magic_eden_nonce}}')
        {% if not is_incremental() %}
        AND evt_block_time >= {{nft_start_date}}
        {% endif %}
        {% if is_incremental() %}
        AND evt_block_time >= date_trunc('day', now() - interval '7' day)
        {% endif %}
)
, erc1155_trades as (

    SELECT CASE when direction = 0 THEN 'buy' ELSE 'sell' END AS trade_category,
          evt_block_time,
          evt_block_number,
          evt_tx_hash,
          contract_address,
          evt_index,
          'Trade' AS evt_type,
          CASE when direction = 0 THEN taker ELSE maker END AS buyer,
          CASE when direction = 0 THEN maker ELSE taker END AS seller,
          erc1155Token AS nft_contract_address,
          erc1155TokenId AS token_id,
          erc1155FillAmount AS number_of_items,
          'erc1155' AS token_standard,
          CASE
               WHEN erc20Token in (0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee, 0x0000000000000000000000000000000000001010)
               THEN 0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270
               ELSE erc20Token
          END AS currency_contract,
          erc20FillAmount AS fill_amount_raw,
          erc20Token as original_erc20_token
    FROM {{ source ('zeroex_polygon', 'ExchangeProxy_evt_ERC1155OrderFilled') }}
    WHERE starts_with(cast(nonce as varchar),'{{magic_eden_nonce}}')
        {% if not is_incremental() %}
        AND evt_block_time >= {{nft_start_date}}
        {% endif %}
        {% if is_incremental() %}
        AND evt_block_time >= date_trunc('day', now() - interval '7' day)
        {% endif %}
)

,erc721_fees as (

    WITH orders as (
    select call_tx_hash, sellOrder as order_data from {{ source('zeroex_polygon','ExchangeProxy_call_buyERC721') }}
    union all
    select call_tx_hash, buyOrder as order_data from {{ source('zeroex_polygon','ExchangeProxy_call_sellERC721') }}
    union all
    select * from (
        select
        call_tx_hash
        ,order_data
        from {{ source('zeroex_polygon','ExchangeProxy_call_batchBuyERC721s') }}
        cross join unnest(sellOrders) as foo(order_data)
        )
    )
    select
    call_tx_hash
    ,maker
    ,erc20TokenAmount
    ,erc721Token
    ,erc721TokenId
    ,sum(amount) filter (where recipient in ({{fee_address_1}}, {{fee_address_2}})) as platform_fee_amount_raw
    ,sum(amount) filter (where recipient not in ({{fee_address_1}}, {{fee_address_2}})) as royalty_fee_amount_raw
    from(
        select call_tx_hash
        ,from_hex(json_extract_scalar(order_data,'$.maker')) as maker
        ,cast(json_extract_scalar(order_data,'$.erc20TokenAmount') as uint256) as erc20TokenAmount
        ,from_hex(json_extract_scalar(order_data,'$.erc721Token')) as erc721Token
        ,cast(json_extract_scalar(order_data,'$.erc721TokenId')as uint256) as erc721TokenId
        ,from_hex(json_extract_scalar(fee_info,'$.recipient')) as recipient
        ,cast(json_extract_scalar(fee_info,'$.amount') as uint256) as amount
        from orders
        cross join unnest(cast(json_extract(order_data,'$.fees') as array<varchar>)) as foo(fee_info)
    )
    group by 1,2,3,4,5
)
,erc1155_fees as (
    WITH orders as (
    select call_tx_hash, sellOrder as order_data from {{ source('zeroex_polygon','ExchangeProxy_call_buyERC1155') }}
    union all
    select call_tx_hash, buyOrder as order_data from {{ source('zeroex_polygon','ExchangeProxy_call_sellERC1155') }}
    union all
    select * from (
        select
        call_tx_hash
        ,order_data
        from {{ source('zeroex_polygon','ExchangeProxy_call_batchBuyERC1155s') }}
        cross join unnest(sellOrders) as foo(order_data)
        )
    )
    select
    call_tx_hash
    ,maker
    ,erc20TokenAmount
    ,erc1155Token
    ,erc1155TokenId
    ,sum(amount) filter (where recipient in ({{fee_address_1}}, {{fee_address_2}})) as platform_fee_amount_raw
    ,sum(amount) filter (where recipient not in ({{fee_address_1}}, {{fee_address_2}})) as royalty_fee_amount_raw
    from(
        select call_tx_hash
        ,from_hex(json_extract_scalar(order_data,'$.maker')) as maker
        ,cast(json_extract_scalar(order_data,'$.erc20TokenAmount') as uint256) as erc20TokenAmount
        ,from_hex(json_extract_scalar(order_data,'$.erc1155Token')) as erc1155Token
        ,cast(json_extract_scalar(order_data,'$.erc1155TokenId')as uint256) as erc1155TokenId
        ,from_hex(json_extract_scalar(fee_info,'$.recipient')) as recipient
        ,cast(json_extract_scalar(fee_info,'$.amount') as uint256) as amount
        from orders
        cross join unnest(cast(json_extract(order_data,'$.fees') as array<varchar>)) as foo(fee_info)
    )
    group by 1,2,3,4,5
)
-- we need to combine the trade and fee data but we also need to correct the fees
-- if the fill_amount from the trade is different from the fill_amount in the fees
, trades as (
    select
    t1.*
    ,coalesce(t1.fill_amount_raw, uint256 '0')
        + coalesce(try_cast(platform_fee_amount_raw*(cast(fill_amount_raw as double)/cast(f1.erc20TokenAmount as double)) as uint256), uint256 '0')
        + coalesce(try_cast(royalty_fee_amount_raw*(cast(fill_amount_raw as double)/cast(f1.erc20TokenAmount as double)) as uint256), uint256 '0')
        as amount_raw
    ,coalesce(try_cast(platform_fee_amount_raw*(fill_amount_raw/cast(f1.erc20TokenAmount as double)) as uint256), uint256 '0') as platform_fee_amount_raw
    ,coalesce(try_cast(royalty_fee_amount_raw*(fill_amount_raw/cast(f1.erc20TokenAmount as double)) as uint256), uint256 '0')  as royalty_fee_amount_raw
    from erc721_trades t1
    left join erc721_fees f1
    on t1.evt_tx_hash = f1.call_tx_hash
        and t1.nft_contract_address = f1.erc721Token
        and t1.token_id = f1.erc721TokenId
    union all
    select
    t2.*
    ,coalesce(t2.fill_amount_raw, uint256 '0')
        + coalesce(try_cast(platform_fee_amount_raw*(cast(fill_amount_raw as double)/cast(f2.erc20TokenAmount as double)) as uint256), uint256 '0')
        + coalesce(try_cast(royalty_fee_amount_raw*(cast(fill_amount_raw as double)/cast(f2.erc20TokenAmount as double)) as uint256), uint256 '0')
        as amount_raw
    ,coalesce(try_cast(platform_fee_amount_raw*(fill_amount_raw/cast(f2.erc20TokenAmount as double)) as uint256), uint256 '0') as platform_fee_amount_raw
    ,coalesce(try_cast(royalty_fee_amount_raw*(fill_amount_raw/cast(f2.erc20TokenAmount as double)) as uint256), uint256 '0')  as royalty_fee_amount_raw
    from erc1155_trades t2
    left join erc1155_fees f2
    on t2.evt_tx_hash = f2.call_tx_hash
        and t2.nft_contract_address = f2.erc1155Token
        and t2.token_id = f2.erc1155TokenId
)


SELECT
  'polygon' AS blockchain,
  'magiceden' AS project,
  'v1' AS version,
  a.evt_tx_hash AS tx_hash,
  date_trunc('day', a.evt_block_time) AS block_date,
  a.evt_block_time AS block_time,
  a.evt_block_number AS block_number,
  a.amount_raw / power(10, erc.decimals) * p.price AS amount_usd,
  a.amount_raw / power(10, erc.decimals) AS amount_original,
  CAST(a.amount_raw as uint256) AS amount_raw,
  CASE WHEN erc.symbol = 'WMATIC' THEN 'MATIC' ELSE erc.symbol END AS currency_symbol,
  a.currency_contract,
  a.token_id,
  a.token_standard,
  a.contract_address AS project_contract_address,
  a.evt_type,
  CAST(NULL AS varchar) AS collection,
  CASE WHEN number_of_items = cast(1 as uint256) THEN 'Single Item Trade' ELSE 'Bundle Trade' END AS trade_type,
  CAST(number_of_items AS uint256) AS number_of_items,
  CAST(NULL AS varchar) AS trade_category,
  buyer,
  seller,
  nft_contract_address,
  agg.name AS aggregator_name,
  agg.contract_address AS aggregator_address,
  t."from" AS tx_from,
  t."to" AS tx_to,
  a.platform_fee_amount_raw,
  CAST(a.platform_fee_amount_raw / power(10, erc.decimals) AS double) AS platform_fee_amount,
  CAST(a.platform_fee_amount_raw / power(10, erc.decimals) * p.price AS double) AS platform_fee_amount_usd,
  coalesce(try(CAST(a.platform_fee_amount_raw / a.amount_raw * 100 as double)), double '0.0') as platform_fee_percentage,
  CAST(a.royalty_fee_amount_raw AS uint256) AS royalty_fee_amount_raw,
  CAST(a.royalty_fee_amount_raw / power(10, erc.decimals) AS double) AS royalty_fee_amount,
  CAST(a.royalty_fee_amount_raw / power(10, erc.decimals) * p.price AS double) AS royalty_fee_amount_usd,
  coalesce(try(CAST(a.royalty_fee_amount_raw / a.amount_raw * 100 AS double)), double '0.0') AS royalty_fee_percentage,
  CAST(NULL AS varbinary) AS royalty_fee_receive_address,
  CAST(NULL AS varchar) AS royalty_fee_currency_symbol,
  cast(a.evt_tx_hash as varchar) || '-' || cast(a.evt_type as varchar)  || '-' || cast(a.evt_index as varchar) ||  '-' || cast(a.token_id as varchar) AS unique_trade_id
FROM trades a
INNER JOIN {{ source('polygon','transactions') }} t ON a.evt_block_number = t.block_number
    AND a.evt_tx_hash = t.hash
    {% if not is_incremental() %}
    AND t.block_time >= {{nft_start_date}}
    {% endif %}
    {% if is_incremental() %}
    AND t.block_time >= date_trunc('day', now() - interval '7' day)
    {% endif %}
LEFT JOIN {{ ref('tokens_erc20') }} erc ON erc.blockchain = 'polygon' AND erc.contract_address = a.currency_contract
LEFT JOIN {{ source('prices', 'usd') }} p ON p.contract_address = a.currency_contract
    AND p.minute = date_trunc('minute', a.evt_block_time)
    {% if not is_incremental() %}
    AND p.minute >= {{nft_start_date}}
    {% endif %}
    {% if is_incremental() %}
    AND p.minute >= date_trunc('day', now() - interval '7' day)
    {% endif %}
LEFT JOIN {{ ref('nft_aggregators') }} agg ON agg.blockchain = 'polygon' AND agg.contract_address = t."to"
