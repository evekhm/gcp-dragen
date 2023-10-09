SELECT J.job_name, J.job_label,  T.task_id,  T.status, J.input_path, J.output_path, T.timestamp,
FROM `dragen_illumina.tasks_status` as T
         JOIN `dragen_illumina.job_array` as J
              on CAST(J.batch_task_index as STRING)=REGEXP_EXTRACT(task_id, r'group0-(\d+)') AND T.job_id=J.job_id
WHERE J.sample_id=@SAMPLE_ID
ORDER BY T.timestamp