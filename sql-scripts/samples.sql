WITH latest AS (
    SELECT *
    FROM `dragen_illumina.tasks_status` t
    WHERE timestamp = (SELECT MAX(timestamp) FROM `dragen_illumina.tasks_status` WHERE task_id = t.task_id )
)
SELECT task_id, sample_id, status, input_path, output_path, timestamp
FROM latest
WHERE task_id != ""
GROUP BY task_id, sample_id, status, timestamp, input_path, output_path
ORDER BY status
