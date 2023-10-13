SELECT
    J.job_name,
    J.job_label,
    J.sample_id,
    T.task_id,
    T.status,
    J.input_path,
    J.output_path,
    T.timestamp  as last_status_time,
    J.timestamp as creation_time
FROM
    `dragen_illumina.tasks_status` AS T
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
ORDER BY
    T.timestamp