with

    -- import ctes
    customers as (select * from {{ source("jaffle_shop", "customers") }}),

    orders as (select * from {{ source("jaffle_shop", "orders") }}),

    payments as (select * from {{ source("stripe", "payment") }}),

    -- logical ctes
    completed_payments as (
        select
            orderid as order_id,
            max(created) as payment_finalized_date,
            sum(amount) / 100.0 as total_amount_paid
        from payments
        where status <> 'fail'
        group by 1
    ),

    paid_orders as (
        select
            orders.id as order_id,
            orders.user_id as customer_id,
            orders.order_date as order_placed_at,
            orders.status as order_status,
            completed_payments.total_amount_paid,
            completed_payments.payment_finalized_date,
            customers.first_name as customer_first_name,
            customers.last_name as customer_last_name
        from orders
        left join completed_payments on orders.id = completed_payments.order_id
        left join customers on orders.user_id = customers.id
    ),

    -- final cte
    final as (
        select
            paid_orders.order_id,
            paid_orders.customer_id,
            paid_orders.order_placed_at,
            paid_orders.order_status,
            paid_orders.total_amount_paid,
            paid_orders.payment_finalized_date,
            paid_orders.customer_first_name,
            paid_orders.customer_last_name,

            -- global transaction sequencing
            row_number() over (order by paid_orders.order_id) as transaction_seq,

            -- customer specific order sequencing
            row_number() over (
                partition by paid_orders.customer_id order by paid_orders.order_id
            ) as customer_sales_seq,

            -- window function replacing customer_orders cte for first order date
            first_value(paid_orders.order_placed_at) over (
                partition by paid_orders.customer_id
                order by paid_orders.order_placed_at
            ) as fdos,

            -- case statement evaluating new vs return orders via window logic
            case
                when
                    (
                        first_value(paid_orders.order_placed_at) over (
                            partition by paid_orders.customer_id
                            order by paid_orders.order_placed_at
                        )
                        = paid_orders.order_placed_at
                    )
                then 'new'
                else 'return'
            end as nvsr,

            -- window function replacing self-join subquery for cumulative clv
            sum(coalesce(paid_orders.total_amount_paid, 0)) over (
                partition by paid_orders.customer_id order by paid_orders.order_id
            ) as customer_lifetime_value

        from paid_orders
    )

-- simple select statement
select *
from final
order by order_id
