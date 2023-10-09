from typing import Optional

from commonek.logging import Logger
import json
import requests
from commonek.helper import get_secret_value

from commonek.params import (
    PROJECT_ID,
    REGION,
    SLACK_WEB_HOOK_SECRET)


def send_slack_message(message: str):
    slack_data = {"text": message}
    webhook_url = get_secret_value(SLACK_WEB_HOOK_SECRET, PROJECT_ID)
    if webhook_url:
        Logger.info(f"send_slack_message - {message}")
        response = requests.post(
            webhook_url,
            data=json.dumps(slack_data),
            headers={"Content-Type": "application/json"},
            allow_redirects=False,
        )
        Logger.info(f"send_slack_message - response {response.text}")


def get_log_url(job_uid: str, task_id: Optional[str] = None):
    # now = datetime.datetime.now(datetime.timezone.utc)
    # last_hour_date_time = datetime.datetime.now() - timedelta(hours=1)
    # now_str = now.strftime("%Y-%m-%dT%H:%M:%S")
    # last_hour_date_time_str = last_hour_date_time.strftime("%Y-%m-%dT%H:%M:%S")

    if task_id:
        task_str = f"resource.labels.task_id%3D%22task%2F{task_id}%2F0%2F0%22"
    else:
        task_str = ""
    log_console_url = f"https://console.cloud.google.com/logs/query;query=logName%3D%22projects%2F" \
                      f"{PROJECT_ID}%2Flogs%2Fbatch_task_logs%22%20OR%20%22projects%2F{PROJECT_ID}%2Flogs" \
                      f"%2Fbatch_agent_logs%22%20labels.job_uid%3D%22" \
                      f"{job_uid}%22%20{task_str}"

    # log_console_url = f"https://console.cloud.google.com/logs/query;query=logName%3D%22projects%2F" \
    #                   f"{PROJECT_ID}%2Flogs%2Fbatch_task_logs%22%20OR%20%22projects%2F{PROJECT_ID}%2Flogs" \
    #                   f"%2Fbatch_agent_logs%22%20labels.job_uid%3D%22" \
    #                   f"{job_uid}%22%20{task_str}timestamp%3E%3D%22{now_str}%22%20timestamp%3C%3D%22{last_hour_date_time_str}%22%20"

    return f" Check the <{log_console_url}|logs> for more info."


def get_output_path_url(output_path: str):
    output_path = output_path.replace("s3://", "").replace("gs://", "")
    path_link = f"https://console.cloud.google.com/storage/browser/{output_path}"
    return f" See the <{path_link}|output directory> for the generated results."


def get_job_url(job_name: str):
    job_url = f"https://console.cloud.google.com/batch/jobsDetail/regions/{REGION}/jobs/" \
              f"{job_name}/details?project={PROJECT_ID}"
    return f"<{job_url}|{job_name}>"


def send_task_message(job_name: str, job_uid: str, task_id: str, status: str, output_path:  Optional[str] = None,
                      sample_id: Optional[str] = None):
    output_path_url = ""
    if output_path:
        output_path_url = get_output_path_url(output_path)
    slack_text = f"_Task_ execution *{status}* for sample_id={sample_id} within {get_job_url(job_name)}." \
                 f"{get_log_url(job_uid, task_id)}{output_path_url}"
    send_slack_message(slack_text)


def send_job_message(job_name: str, job_uid: str, status: str):
    slack_text = f"_Job_ execution *{status}* for {get_job_url(job_name)}." \
                 f" {get_log_url(job_uid)}"
    send_slack_message(slack_text)

# import slack
# import os
#
# from tao_common.secretmanager import SecretManager
# from tao_common.utils import validate_dict_contains
#
#
# GCP_PROJECT = os.environ["GCP_PROJECT"]
# REQUIRED_SLACK_CONTEXT = ["channel", "text"]
#
#
# def post_to_slack(data: dict) -> None:
#     validate_dict_contains(data, REQUIRED_SLACK_CONTEXT)
#     for _ in range(2):
#         try:
#             slack = Slack()
#             slack.chat_post_message(data.get("channel"), text=data.get("text"))
#             return
#         except Exception:
#             # retry on fail
#             continue
#
#
# class Slack:
#     """Class for working with Slack python client."""
#
#     def __init__(self, secret_name="slack-api-token"):
#         """Initialize a class instance."""
#
#         self.token = SecretManager(GCP_PROJECT).get_secret(secret_name)
#         self.client = slack.WebClient(token=self.token)
#
#     # pylint: disable=dangerous-default-value
#     def chat_post_message(self, channel, blocks=[], text=""):
#         """Post a message to Slack using the App API token."""
#         return self.client.chat_postMessage(
#             channel=channel,
#             blocks=blocks,
#             text=text,
#             unfurl_media=False,
#         )
#
#     # pylint: disable=dangerous-default-value
#     def chat_update(self, channel, timestamp, blocks=[], text=""):
#         """Update a previously-posted Slack message."""
#         return self.client.chat_update(
#             channel=channel,
#             blocks=blocks,
#             text=text,
#             ts=timestamp,
#             unfurl_media=False,
#         )