SELECT
    COUNTIF(status = "SCHEDULED") as  TOTAL,
    COUNTIF(status = "SCHEDULED") as SCHEDULED,
    COUNTIF(status = "RUNNING") as RUNNING,
    COUNTIF(status = "SUCCEEDED") as SUCCEEDED,
    COUNTIF(status = "FAILED") as FAILED,
FROM `dragen_illumina.tasks_status`

