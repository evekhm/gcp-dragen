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
                        task_id = t.task_id ) )
SELECT
    J.job_name,
    J.job_label,
    CAST(REGEXP_EXTRACT(task_id, r'group0-(\d+)') AS INTEGER) AS batch_index,
    J.sample_id,
    T.status,
    J.input_path,
    J.output_path,
    J.input_type,
    T.timestamp  as last_status_time,
    J.timestamp as creation_time
FROM
    latest AS T
        JOIN
    `dragen_illumina.job_array` AS J
    ON
                CAST(J.batch_task_index AS STRING)=REGEXP_EXTRACT(task_id, r'group0-(\d+)')
            AND T.job_id=J.job_id
WHERE
    (J.sample_id=@SAMPLE_ID
        OR @SAMPLE_ID="")
  AND (J.job_label=@LABEL
    OR @LABEL="")
  AND (J.timestamp >= CAST(@AFTER_TIME AS datetime))
  AND (J.timestamp <= CAST(@BEFORE_TIME AS datetime))
GROUP BY
    T.job_id,
    T.task_id,
    J.sample_id,
    T.status,
    last_status_time,
    J.input_path,
    J.output_path,
    J.input_type,
    J.job_label,
    J.job_name,
    creation_time
ORDER BY
    status,
    batch_index,
    creation_time