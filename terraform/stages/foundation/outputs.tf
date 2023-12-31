/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

output "vpc_network" {
  value =  var.vpc_network
}

output "vpc_subnetwork" {
  value =  var.vpc_subnetwork
}

output "ip_cidr_range" {
  value =  var.ip_cidr_range
}

output "hmac_access_file_name" {
  value = module.hmac_keys.hmac_access_file_name
}

output "hmac_secret_file_name" {
  value = module.hmac_keys.hmac_secret_file_name
}
