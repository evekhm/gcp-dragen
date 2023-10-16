import os
import sys
import argparse
sys.path.append(os.path.join(os.path.dirname(__file__), '../common/src'))

# os.environ["PROJECT_ID"] = "YOUR_PROJECT_ID_HERE"
# # The channel id of the channel you want to send the message to
# os.environ["SLACK_CHANNEL"] = "YOUR_CHANNEL_ID_HERE"

from commonek.slack import Slack
from commonek.params import SLACK_API_TOKEN_SECRET_NAME, PROJECT_ID


def get_args():
    # Read command line arguments
    args_parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description="""
      Script to test Slack Integration. Expects following Env variable to be set: PROJECT_ID,  SLACK_CHANNEL and 
      GCP secret created with Slack Token $SLACK_API_TOKEN_SECRET_NAME.
      """,
        epilog="""
      Examples:

      python slack_test.py -m="Hello World Message test! [-c="channel-id"]"
      """,
    )

    args_parser.add_argument(
        "-m",
        dest="message",
        help="Message to be sent to the Channel",
    )
    args_parser.add_argument(
        "-c",
        dest="channel",
        help="Slack Channel",
    )
    return args_parser


if __name__ == "__main__":
    parser = get_args()
    args = parser.parse_args()

    slack_test = Slack()

    channel_id = args.channel
    if not channel_id:
        channel_id = os.getenv("SLACK_CHANNEL")

    if not channel_id:
        print("Please, either set env variable SLACK_CHANNEL to point to the Slack channel, "
              "or provide channel as a parameter into the Python function using option `-c`")
    else:
        print(f"Testing Slack message using channel={channel_id} and message={args.message} and "
              f"secret token of {SLACK_API_TOKEN_SECRET_NAME} inside project={PROJECT_ID}")
        slack_test.chat_post_message(channel=channel_id, text=args.message)
