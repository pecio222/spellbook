{{config(
    tags=['dunesql'],
    alias = alias('trades'),
    post_hook='{{expose_spells(\'["optimism"]\',
                "project",
                "rubicon",
                \'["msilb7, denver"]\') }}'
)}}

{% set rubi_models = [
ref('rubicon_optimism_trades'),
ref('rubicon_arbitrum_trades'), 
ref('rubicon_base_trades')
] %}


SELECT *
FROM (
    {% for r_model in rubi_models %}
    SELECT
        blockchain,
        project,
        version,
        block_month,
        block_date,
        block_time,
        token_bought_symbol,
        token_sold_symbol,
        token_pair,
        token_bought_amount,
        token_sold_amount,
        token_bought_amount_raw,
        token_sold_amount_raw,
        amount_usd,
        token_bought_address,
        token_sold_address,
        taker,
        maker,
        project_contract_address,
        tx_hash,
        tx_from,
        tx_to,
        evt_index
    FROM {{ r_model }}
    {% if not loop.last %}
    UNION ALL
    {% endif %}
    {% endfor %}
)
