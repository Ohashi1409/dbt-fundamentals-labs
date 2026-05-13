with summary as (
    select 
        customer_id,
        order_date,
        {{ dbt_utils.generate_surrogate_key(['customer_id', 'order_date']) }} as pk_summary,
        count(*) as c
    from {{ ref('stg_jaffle_shop__orders') }}
    group by 1, 2
    order by customer_id
),

final as (
    select 
        pk_summary, 
        customer_id,
        order_date,
        c
    from summary
)

select * from final
