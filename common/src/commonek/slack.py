import ssl
from typing import Optional

import certifi
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

from commonek.helper import get_secret_value
from commonek.logging import Logger
from commonek.params import (
    PROJECT_ID,
    REGION,
    SLACK_CHANNEL,
    SLACK_API_TOKEN_SECRET_NAME)


class Slack:
    """Class for working with Slack python client."""

    def __init__(self):
        """Initialize a class instance."""
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        self.token = get_secret_value(secret_name=SLACK_API_TOKEN_SECRET_NAME, project_id=PROJECT_ID)
        self.client = WebClient(token=self.token, ssl=ssl_context)

    # pylint: disable=dangerous-default-value
    def chat_post_message(self, channel, blocks=[], text=""):
        """Post a message to Slack using the App API token."""
        return self.client.chat_postMessage(
            channel=channel,
            text=text,
            blocks=blocks,
            unfurl_media=False,
        )

    # pylint: disable=dangerous-default-value
    def chat_update(self, channel, timestamp, blocks=[], text=""):
        """Update a previously-posted Slack message."""
        return self.client.chat_update(
            channel=channel,
            blocks=blocks,
            text=text,
            ts=timestamp,
            unfurl_media=False,
        )


def get_log_url(job_uid: str, task_id: Optional[str] = None):
    if task_id:
        task_str = f"resource.labels.task_id%3D%22task%2F{task_id}%2F0%2F0%22"
    else:
        task_str = ""
    log_console_url = f"https://console.cloud.google.com/logs/query;query=logName%3D%22projects%2F" \
                      f"{PROJECT_ID}%2Flogs%2Fbatch_task_logs%22%20OR%20%22projects%2F{PROJECT_ID}%2Flogs" \
                      f"%2Fbatch_agent_logs%22%20labels.job_uid%3D%22" \
                      f"{job_uid}%22%20{task_str}"
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
    if not SLACK_CHANNEL:
        return

    output_path_url = ""
    if output_path:
        output_path_url = get_output_path_url(output_path)
    slack_text = f"_Task_ execution *{status}* for sample_id={sample_id} within {get_job_url(job_name)}." \
                 f"{get_log_url(job_uid, task_id)}{output_path_url}"
    try:
        slack_client = Slack()  # since token can change

        Logger.info(f"send_task_message - text={slack_text} channel={SLACK_CHANNEL}")
        slack_client.chat_post_message(channel=SLACK_CHANNEL, text=slack_text)
    except SlackApiError as exc:
        Logger.error(f"send_task_message text={slack_text} channel={SLACK_CHANNEL}- failed on {exc}")


def send_job_message(job_name: str, job_uid: str, status: str):
    if not SLACK_CHANNEL:
        return

    slack_text = f"_Job_ execution *{status}* for {get_job_url(job_name)}." \
                 f" {get_log_url(job_uid)}"
    try:
        slack_client = Slack()

        Logger.info(f"send_task_message - text={slack_text} channel={SLACK_CHANNEL}")
        slack_client.chat_post_message(channel=SLACK_CHANNEL, text=slack_text)
        return
    except SlackApiError as exc:
        Logger.error(f"send_job_message text={slack_text} channel={SLACK_CHANNEL}- failed on {exc}")