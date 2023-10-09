WITH latest AS (
    SELECT *
    FROM `dragen_illumina.tasks_status` t
    WHERE timestamp = (SELECT MAX(timestamp) FROM `dragen_illumina.tasks_status` WHERE task_id = t.task_id )
)

SELECT J.job_name, J.job_label, CAST(REGEXP_EXTRACT(task_id, r'group0-(\d+)') AS INTEGER) as batch_index, J.sample_id, T.status,J.input_path, J.output_path,   J.input_type,  T.timestamp,
FROM latest as T
         JOIN `dragen_illumina.job_array` as J
              on CAST(J.batch_task_index as STRING)=REGEXP_EXTRACT(task_id, r'group0-(\d+)') AND T.job_id=J.job_id
GROUP BY T.job_id, T.task_id, J.sample_id, T.status, T.timestamp, J.input_path, J.output_path, J.input_type, J.job_label, J.job_name
ORDER BY status, batch_index