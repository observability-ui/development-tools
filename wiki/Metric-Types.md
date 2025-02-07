There are four total metric types which are available for Prometheus use. These metrics are implemented in client libraries, but not used on the backed. Once scrapped the data is flattened and stored as untyped time series data.

## Counter
A single value which can only increase. Used to track things like total number of requests
## Gauge
A single value which can increase and decrease. Used to track values over time (temperature) or an increasing value which may need to also decrease (successful sale that is then refunded).
## Histogram
Samples observations like request durations or sizes. These are broken up into three segments
### Cumulative Counters
Exposed as `<basename>_bucket{le="<upper inclusive bound>"}`. These are the singular samples that occur between scrapes.
### Total Sum
Exposed as `<basename>_sum`
### Count of all events
Exposed as `<basename>_count` or `<basename>_bucket{le="+Inf"}`
## Summary
Samples observations while also providing quartile data
- streaming **φ-quantiles** (0 ≤ φ ≤ 1) of observed events, exposed as `<basename>{quantile="<φ>"}`
- the **total sum** of all observed values, exposed as `<basename>_sum`
- the **count** of events that have been observed, exposed as `<basename>_count`
