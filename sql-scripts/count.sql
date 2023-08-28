WITH latest AS (
    SELECT *
    FROM `dragen_illumina.tasks_status` t
    WHERE timestamp = (SELECT MAX(timestamp) FROM `dragen_illumina.tasks_status` WHERE task_id = t.task_id )
)
SELECT
    Count(1) as TOTAL,
    COUNTIF(status = "RUNNING") as RUNNING,
    COUNTIF(status = "SUCCEEDED") as SUCCEEDED,
    COUNTIF(status = "FAILED") as FAILED,
FROM latest
WHERE task_id != ""
