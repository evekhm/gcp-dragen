WITH
    latest AS (
        SELECT
            J.timestamp AS timestamp,
            J.job_label AS job_label,
            J.sample_id AS sample_id,
            T.task_id AS task_id,
            T.status AS status
        FROM
            `dragen_illumina.tasks_status` T
                JOIN
            `dragen_illumina.job_array` AS J
            ON
                        CAST(J.batch_task_index AS STRING)=REGEXP_EXTRACT(task_id, r'group0-(\d+)')
                    AND T.job_id=J.job_id
        WHERE
                T.timestamp = (
                SELECT
                    MAX(timestamp)
                FROM
                    `dragen_illumina.tasks_status`
                WHERE
                        task_id = T.task_id) )
SELECT
    COUNT(1) AS TOTAL,
    COUNTIF(latest.status = "RUNNING") AS RUNNING,
    COUNTIF(latest.status = "VERIFIED_FAILED"
        OR latest.status = "VERIFIED_OK") AS SUCCEEDED,
    COUNTIF(latest.status = "FAILED") AS FAILED,
    COUNTIF(latest.status = "VERIFIED_OK") AS VERIFIED_OK,
    COUNTIF(latest.status = "VERIFIED_FAILED") AS VERIFIED_FAILED,
FROM
    latest
WHERE
    (latest.sample_id=@SAMPLE_ID
        OR @SAMPLE_ID="")
  AND (latest.job_label=@LABEL
    OR @LABEL="")
  AND (latest.timestamp >= CAST(@AFTER_TIME AS datetime))
  AND (latest.timestamp <= CAST(@BEFORE_TIME AS datetime))