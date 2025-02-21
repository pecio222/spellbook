{{config(
        tags=['dunesql'],
        alias = alias('balancer_v2_gauges_arbitrum'),
        post_hook='{{ expose_spells(\'["arbitrum"]\',
                                    "sector",
                                    "labels",
                                    \'["jacektrocinski"]\') }}')}}

SELECT distinct
    'arbitrum' AS blockchain,
    gauge.gauge AS address,
    'arb:' || pools.name AS name,
    'balancer_v2_gauges' AS category,
    'balancerlabs' AS contributor,
    'query' AS source,
    TIMESTAMP '2022-01-13'  AS created_at,
    NOW() AS updated_at,
    'balancer_v2_gauges_arbitrum' AS model_name,
    'identifier' AS label_type
FROM
    {{ source('balancer_ethereum', 'ArbitrumRootGaugeFactory_evt_ArbitrumRootGaugeCreated') }} gauge
    LEFT JOIN {{ source('balancer_v2_arbitrum', 'ChildChainLiquidityGaugeFactory_evt_RewardsOnlyGaugeCreated') }} streamer ON gauge.recipient = streamer.streamer
    LEFT JOIN {{ ref('labels_balancer_v2_pools_arbitrum') }} pools ON pools.address = streamer.pool
UNION ALL
SELECT distinct
    'arbitrum' AS blockchain,
    gauge.gauge AS address,
    'arb:' || pools.name AS name,
    'balancer_v2_gauges' AS category,
    'balancerlabs' AS contributor,
    'query' AS source,
    TIMESTAMP '2022-01-13'  AS created_at,
    NOW() AS updated_at,
    'balancer_v2_gauges_arbitrum' AS model_name,
    'identifier' AS label_type
FROM
    {{ source('balancer_ethereum', 'CappedArbitrumRootGaugeFactory_evt_GaugeCreated') }} gauge
    INNER JOIN {{ source('balancer_ethereum', 'CappedArbitrumRootGaugeFactory_call_create') }} call ON call.call_tx_hash = gauge.evt_tx_hash
    LEFT JOIN {{ source('balancer_v2_arbitrum', 'ChildChainLiquidityGaugeFactory_evt_RewardsOnlyGaugeCreated') }} streamer ON streamer.streamer = call.recipient
    LEFT JOIN {{ ref('labels_balancer_v2_pools_arbitrum') }} pools ON pools.address = streamer.pool
