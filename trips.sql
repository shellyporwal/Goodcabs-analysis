
select * from city_target_passenger_rating
select * from dim_city
select * from dim_date
select * from dim_repeat_trip_distribution
select * from fact_passenger_summary
select * from fact_trips
select * from monthly_target_new_passengers
select * from monthly_target_trips

-- top 3 cities by total trips
WITH city_trip_counts AS (
    SELECT
        f.city_id,
        d.city_name,
        COUNT(f.trip_id) AS total_trips
    FROM fact_trips f
    JOIN dim_city d
        ON f.city_id = d.city_id
    GROUP BY f.city_id, d.city_name
)

SELECT *
FROM city_trip_counts
ORDER BY total_trips DESC
LIMIT 3;

-- bottom 3 cities by total trips
with city_trip_counts as (select f.city_id,d.city_name,count(f.trip_id) as total_trips from fact_trips f join dim_city d on f.city_id=d.city_id group by f.city_id,d.city_name )
select * from city_trip_counts order by  total_trips asc limit 3

--Average fair per trip by city

select f.city_id,d.city_name,round(avg(f.fare_amount),2) as average_fare,ROUND(AVG(f.distance_travelled_km), 2) AS avg_distance_per_trip,ROUND(SUM(f.fare_amount) / NULLIF(SUM(f.distance_travelled_km), 0), 2) AS revenue_per_km from fact_trips f join dim_city d on f.city_id=d.city_id group by f.city_id,d.city_name order by average_fare desc


 -- Average ratings by city and passenger type

 with cte as (select f.city_id,d.city_name,f.passenger_type,round(avg(f.passenger_rating),2) as average_passenger_rating ,round(avg(f.driver_rating),2) as average_driver_rating, round((AVG(f.passenger_rating) + AVG(f.driver_rating)) / 2,2) AS avg_composite_rating  from fact_trips f join  dim_city d on f.city_id=d.city_id group by f.city_id,d.city_name,f.passenger_type)
 ,per as (select  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY avg_composite_rating)  AS p90,
        PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY avg_composite_rating)   AS p10 from cte)

select c.city_name,c.passenger_type,c.average_passenger_rating,c.average_driver_rating,c.avg_composite_rating,case when c.avg_composite_rating >= p.p90 then 'top_city' when c.avg_composite_rating <= p.p10 then 'bottom_city' else 'mid_city' end as performance_category  FROM cte c
CROSS JOIN per p ORDER BY avg_composite_rating DESC



-- peak and low demand months by city

with data as(select f.city_id,d.city_name,m.month_name,count(f.trip_id) as total_trips,rank() over(partition by d.city_name order by count(f.trip_id) desc)  as rank_high,
 SUM(COUNT(f.trip_id)) OVER (
            PARTITION BY d.city_name
        ) AS city_total_trips,rank() over(partition by d.city_name order by count(f.trip_id) )  as rank_low from fact_trips f join dim_city d on f.city_id=d.city_id join dim_date m on m.date=f.date 
group by f.city_id,d.city_name,m.month_name)

select city_name,month_name,total_trips, ROUND(
        total_trips::numeric * 100
        / city_total_trips,
        2
    ) AS trip_contribution_pct,

    case when rank_high=1 then 'Peak_demand_month' when rank_low=1 then 'Low_demand_month' end as demand_category FROM data where rank_high=1 or rank_low=1

--or 

SELECT
    city_name,

    MAX(
        CASE
            WHEN rank_high = 1 THEN month_name
        END
    ) AS peak_demand_month,

    MAX(
        CASE
            WHEN rank_low = 1 THEN month_name
        END
    ) AS low_demand_month

FROM data

GROUP BY city_name

ORDER BY city_name;


--weekend vs weekday trip demand by city

with data as(select f.city_id,c.city_name,d.day_type,count(f.trip_id) as total_trips from 
fact_trips f join dim_city c on f.city_id=c.city_id join dim_date d on f.date=d.date group by f.city_id,c.city_name,d.day_type
)

select city_name,SUM(total_trips) AS overall_total_trips,max(case when day_type='Weekday' then total_trips end) as Weekday_trips, ROUND(
        MAX(
            CASE
                WHEN day_type = 'Weekday'
                THEN total_trips
            END
        )::numeric * 100
        / SUM(total_trips),
        2
    ) AS weekday_trip_pct,


max(case when day_type='Weekend' then total_trips  end) as Weekend_trips ,
 ROUND(
        MAX(
            CASE
                WHEN day_type = 'Weekend'
                THEN total_trips
            END
        )::numeric * 100
        / SUM(total_trips),
        2
    ) AS weekend_trip_pct from data group by city_name

--repeat passengers count

with freq as(select c.city_name, trip_count,sum(repeat_passenger_count) as repeat_passengers_count from dim_repeat_trip_distribution r join dim_city c on r.city_id=c.city_id group by c.city_name,trip_count)
, total_repeat_passengers as (select sum(repeat_passenger_count) as total_repeat_passenger_count from dim_repeat_trip_distribution )

select city_name,trip_count,round(repeat_passengers_count :: numeric * 100 /total_repeat_passenger_count ,2) as freq_per FROM freq f
CROSS JOIN total_repeat_passengers t  



ORDER BY city_name,freq_per desc;



--monthly target achievement analysis


with actuals as(select f.city_id,c.city_name,d.start_of_month AS month,count(f.trip_id) as total_trips,round(avg(f.passenger_rating),2) as average_passenger_rating,sum(case when f.passenger_type='new' then 1 else 0 end ) as total_new_customers from fact_trips f join dim_city c on f.city_id=c.city_id join dim_date d on f.date=d.date  group by f.city_id,c.city_name,d.start_of_month )

select a.city_id,a.city_name,to_char(a.month,'Month'),a.total_trips,mt.total_target_trips,
case when a.total_trips>mt.total_target_trips then 'Exceeded'
      when a.total_trips<mt.total_target_trips then 'Missed'
	  else 'Fulfilled' end as trip_status,
	   ROUND(
        (a.total_trips - mt.total_target_trips)::numeric
        * 100
        / mt.total_target_trips,
        2
    ) AS trip_pct_diff,

	a.average_passenger_rating,pr.target_avg_passenger_rating,
	case when a.average_passenger_rating>pr.target_avg_passenger_rating then 'Exceeded'
      when a.average_passenger_rating<pr.target_avg_passenger_rating then 'Missed'
	  else 'Fulfilled' end as rating_status,
	   ROUND(
        (a.average_passenger_rating -pr.target_avg_passenger_rating)::numeric
        * 100
        /pr.target_avg_passenger_rating,
        2
    ) AS rating_pct_diff
,a.total_new_customers,np.target_new_passengers,
case when a.total_new_customers> np.target_new_passengers then 'Exceeded'
      when a.total_new_customers<np.target_new_passengers then 'Missed'
	  else 'Fulfilled' end as new_cust_status,
	   ROUND((a.total_new_customers
        - np.target_new_passengers)::numeric
        * 100
        /np.target_new_passengers,
        2
    ) AS new_cust_pct_diff


FROM actuals a

JOIN monthly_target_trips mt
    ON a.city_id = mt.city_id
   AND a.month = mt.month
JOIN monthly_target_new_passengers np
    ON a.city_id = np.city_id
   AND a.month = np.month
JOIN city_target_passenger_rating pr
    ON a.city_id = pr.city_id
	
ORDER BY
    a.city_name,
    a.month;

	
--lowest and highest repeat passengers by city


with data as (select c.city_name,sum(f.repeat_passengers) as repeat_passengers,sum(f.total_passengers) as total_passengers ,ROUND(
            SUM(f.repeat_passengers)::numeric * 100
            / SUM(f.total_passengers),
            2
        ) as repeat_passenger_percent from fact_passenger_summary f join dim_city c on f.city_id=c.city_id GROUP BY c.city_name

) ,ranked as(

select *,rank() over( order by repeat_passenger_percent desc) as rank_high,
rank() over( order by repeat_passenger_percent ) as rank_low
from data
)

SELECT
    city_name,
    repeat_passengers,
    total_passengers,
    repeat_passenger_percent,

    CASE
        WHEN rank_high <= 2
            THEN 'TOP_2'

        WHEN rank_low <= 2
            THEN 'BOTTOM_2'
    END AS category

FROM ranked

WHERE rank_high <= 2
   OR rank_low <= 2

ORDER BY repeat_passenger_percent DESC;

--lowest and highest repeat passengers by month 

with data as (
select d.month_name , sum(f.repeat_passengers) as repeat_passengers,sum(f.total_passengers) as total_passengers ,ROUND(
    SUM(f.repeat_passengers)::numeric * 100
            / SUM(f.total_passengers),2)as repeat_passenger_percent from fact_passenger_summary f join dim_date d on d.start_of_month=f.month GROUP BY d.month_name 
),ranked as(

select *,rank() over( order by repeat_passenger_percent desc) as rank_high,
rank() over( order by repeat_passenger_percent ) as rank_low
from data
)
select month_name,repeat_passengers,total_passengers,
    repeat_passenger_percent,
	case when rank_high<=2 then 'Top_2'
	when rank_low <= 2 then 'Bottom_2'
	end as category

FROM ranked

WHERE rank_high <= 2
   OR rank_low <= 2

ORDER BY repeat_passenger_percent DESC;


-- Highest or lowest revenue city

with data as(
select  c.city_name,sum(f.fare_amount) as revenue from fact_trips f join dim_city c on f.city_id=c.city_id group by c.city_name

),total_revenue  as (
select sum(revenue) as total_revenue from data)
 
select d.city_name,round(d.revenue::numeric * 100/t.total_revenue,2) as rev_contri_per ,rank() over(order  by round(d.revenue::numeric * 100/t.total_revenue,2) desc) as rnk from data d cross join total_revenue t


-- Highest or lowest revenue month

with data as(
select  d.month_name,sum(f.fare_amount) as revenue from fact_trips f join dim_date d on f.date=d.date group by d.month_name

),total_revenue  as (
select sum(revenue) as total_revenue from data)
 
select d.month_name ,round(d.revenue::numeric * 100/t.total_revenue,2) as rev_contri_per ,rank() over(order  by round(d.revenue::numeric * 100/t.total_revenue,2) desc) as rnk from data d cross join total_revenue t

