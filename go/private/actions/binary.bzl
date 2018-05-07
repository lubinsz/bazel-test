# Copyright 2014 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_C_SHARED",
    "LINKMODE_C_ARCHIVE",
)
load(
    "@io_bazel_rules_go//go/private:common.bzl",
    "ARCHIVE_EXTENSION",
)

def emit_binary(go,
    name = "",
    source = None,
    test_archives = [],
    gc_linkopts = [],
    linkstamp = None,
    version_file = None,
    info_file = None,
    executable = None):
  """See go/toolchains.rst#binary for full documentation."""

  if name == "" and executable == None:
    fail("either name or executable must be set")

  archive = go.archive(go, source)
  if not executable:
    extension = go.exe_extension
    if go.mode.link == LINKMODE_C_SHARED:
      name = "lib" + name # shared libraries need a "lib" prefix in their name
      extension = go.shared_extension
    elif go.mode.link == LINKMODE_C_ARCHIVE:
      extension = ARCHIVE_EXTENSION
    executable = go.declare_file(go, name=name, ext=extension)
  go.link(go,
      archive=archive,
      test_archives=test_archives,
      executable=executable,
      gc_linkopts=gc_linkopts,
      linkstamp=linkstamp,
      version_file=version_file,
      info_file=info_file,
  )

  return archive, executable
