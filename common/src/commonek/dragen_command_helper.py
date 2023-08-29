"""
Copyright 2022 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""
import re
from commonek.params import CRAM_INPUT, FASTQ_INPUT, FASTQ_LIST_INPUT


class DragenCommand:
    def __init__(self, command_line: str):
        self.script = command_line

    def __obscure_sensitive_info(self):
        def obscure_key(key_name, command):
            key_value = get_parameter_value(command, key_name)
            if key_value:
                return command.replace(key_value, ('X' * len(key_value)))
            return command

        license_string = get_parameter_value(self.script, "--lic-server")
        match = re.match(r"https://(.+)@license.edicogenome.com", license_string)
        clean_command = self.script
        if match and len(match.groups()) >= 1:
            lic = match.group(1)
            clean_command = clean_command.replace(lic, ('X' * len(lic)))

        keys_to_obscure = ["--apikey", "--s3-secret-key", "--s3-access-key"]
        for key in keys_to_obscure:
            clean_command = obscure_key(key, clean_command)
        return clean_command

    def __str__(self):
        return self.__obscure_sensitive_info()

    def get_input(self):
        if self.get_input_type() == CRAM_INPUT:
            return get_parameter_value(self.script, "--cram-input")
        if self.get_input_type() == FASTQ_LIST_INPUT:
            return get_parameter_value(self.script, "--fastq-list")
        if self.get_input_type() == FASTQ_INPUT:
            param1 = get_parameter_value(self.script, "-1")
            param2 = get_parameter_value(self.script, "-2")
            return ",".join([param1, param2])

    def get_input_type(self):
        if "--cram-input" in self.script:
            return CRAM_INPUT
        if "--fastq-list" in self.script:
            return FASTQ_LIST_INPUT
        if "-1 " in self.script and "-2 " in self.script:
            return FASTQ_INPUT

    def get_output(self):
        return get_parameter_value(self.script, "--output-directory")

    def get_sample_id(self):
        return get_parameter_value(self.script, "--vc-sample-name")


def get_parameter_value(command: str, parameter_name: str):
    if parameter_name in command:
        try:
            return command.split(parameter_name)[1].strip().split(" ")[0]
        except Exception:
            return ""




