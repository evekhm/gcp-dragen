WITH
    latest AS (
        SELECT
            *
        FROM
            `dragen_illumina.tasks_status` t
        WHERE
                timestamp = (
                SELECT
                    MAX(timestamp)
                FROM
                    `dragen_illumina.tasks_status`
                WHERE
                        task_id = t.task_id
                  AND status!= "VERIFIED_OK"
                  AND status != "VERIFIED_FAILED")
          AND task_id != "" ),
    verified AS (
        SELECT
            *
        FROM
            `dragen_illumina.tasks_status` t
        WHERE
                timestamp = (
                SELECT
                    MAX(timestamp)
                FROM
                    `dragen_illumina.tasks_status`
                WHERE
                        task_id = t.task_id) )
SELECT
    COUNT(1) AS TOTAL,
    COUNTIF(latest.status = "RUNNING") AS RUNNING,
    COUNTIF(latest.status = "SUCCEEDED") AS SUCCEEDED,
    COUNTIF(latest.status = "FAILED") AS FAILED,
    COUNTIF(verified.status = "VERIFIED_OK") AS VERIFIED_OK,
    COUNTIF(verified.status = "VERIFIED_FAILED") AS VERIFIED_FAILED,
FROM
    latest
        INNER JOIN
    verified
    ON
            latest.task_id = verified.task_id