# E-Commerce Delivery Performance & Customer Experience Analysis

**Tools:** PostgreSQL, SQL (CTEs, window functions), Power BI, DAX
**Data:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce): 96,470 delivered orders across 8 relational tables, Sept 2016 to Aug 2018

![Dashboard](dashboard.png)

## Business Question

What drives late deliveries, how much do they hurt customer satisfaction, and where should the business focus to fix them?

## Key Findings

**1. Satisfaction falls off a cliff at 4 days late.**
Customers tolerate short delays, but negative reviews (1 to 2 stars) rise sharply once an order is 4+ days past its promised date.

| Delivery vs. promised date | Orders | Avg review | Negative reviews |
|---|---|---|---|
| 7+ days early | 70,929 | 4.32 | 8.9% |
| On time / slightly early | 17,234 | 4.20 | 10.2% |
| 1-3 days late | 2,636 | 3.77 | 19.1% |
| 4-7 days late | 1,773 | 2.32 | 61.3% |
| 8+ days late | 3,252 | 1.73 | 78.3% |

**2. Late first orders reduce repeat business.**
Customers whose first order arrived late made a repeat purchase 2.50% of the time, compared with 3.05% for on-time first orders, an 18% lower repeat rate. This is a correlation; regional factors may contribute to both.

**3. Delivery estimates are heavily padded.**
74% of orders arrive 7+ days before the promised date. Early orders earn the highest reviews, but overly long estimates may discourage purchases at checkout.

**4. Problems are concentrated in specific regions and sellers.**
- Rio de Janeiro (RJ), the second-largest market with 12,350 orders, has a 13.5% late rate, more than double São Paulo's 5.9%.
- 32 of 425 high-volume sellers (50+ orders) have late rates of 15% or more.

**5. Revenue exposure.**
4,136 late orders received negative reviews, representing R$639K (4.84%) of product revenue.

## Recommendations

1. **Intervene before day 4.** Flag orders trending late and send proactive updates or small credits before they cross the 4-day threshold where reviews collapse.
2. **Prioritize Rio de Janeiro.** Audit carrier performance in RJ, where high volume and a high late rate combine for the largest impact.
3. **Hold sellers accountable.** Share late-rate scorecards with the 32 underperforming high-volume sellers and set shipping-time targets.
4. **Test tighter delivery estimates.** A/B test more accurate estimates to see whether shorter promised windows improve conversion without raising late rates.

## Data Quality Notes

- Restricted analysis to orders with status `delivered` and a non-null delivery date.
- Some orders have multiple reviews; scores were averaged per order.
- About 650 delivered orders have no review and are excluded from review-based metrics.
- Revenue figures are in Brazilian reais (R$).

## Repository Contents

| File | Description |
|---|---|
| `olist_operations_analysis.sql` | Table creation, data loading, quality checks, analysis view, and 7 analysis queries |
| `olist_delivery_dashboard.pbix` | Power BI dashboard |
| `dashboard.png` | Dashboard screenshot |

## How to Reproduce

1. Download the dataset from Kaggle and load it into PostgreSQL using Steps 1 and 2 of the SQL file.
2. Run `ANALYZE;`, then Steps 3 through 5.
3. Open the `.pbix` file in Power BI Desktop and point the PostgreSQL connection at your local `olist` database.
