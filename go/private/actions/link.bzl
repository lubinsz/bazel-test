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
    "@io_bazel_rules_go//go/private:common.bzl",
    "sets",
    "as_iterable",
)
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_NORMAL",
)

def emit_link(go,
    archive = None,
    test_archives = [],
    executable = None,
    gc_linkopts = [],
    linkstamp=None,
    version_file=None,
    info_file=None):
  """See go/toolchains.rst#link for full documentation."""

  if archive == None: fail("archive is a required parameter")
  if executable == None: fail("executable is a required parameter")
  if not go.builders.link:
    return _bootstrap_link(go, archive, executable, gc_linkopts)

  #TODO: There has to be a better way to work out the rpath
  config_strip = len(go._ctx.configuration.bin_dir.path) + 1
  pkg_depth = executable.dirname[config_strip:].count('/') + 1

  ld = None
  extldflags = []
  if go.cgo_tools:
    ld = go.cgo_tools.compiler_executable
    extldflags.extend(go.cgo_tools.options)
  extldflags.extend(["-Wl,-rpath,$ORIGIN/" + ("../" * pkg_depth)])

  gc_linkopts, extldflags = _extract_extldflags(gc_linkopts, extldflags)

  args = go.args(go)

  # Add in any mode specific behaviours
  link_external = False
  if go.mode.race:
    gc_linkopts.append("-race")
  if go.mode.msan:
    gc_linkopts.append("-msan")
  if go.mode.static:
    extldflags.append("-static")
  if go.mode.link != LINKMODE_NORMAL:
    args.add(["-buildmode", go.mode.link])
    link_external = True

  if link_external:
    gc_linkopts.extend(["-linkmode", "external"])

  # Build the set of transitive dependencies. Currently, we tolerate multiple
  # archives with the same importmap (though this will be an error in the
  # future), but there is a special case which is difficult to avoid:
  # If a go_test has internal and external archives, and the external test
  # transitively depends on the library under test, we need to exclude the
  # library under test and use the internal test archive instead. 
  deps = depset(transitive = [d.transitive for d in archive.direct])
  dep_args = ["{}={}={}".format(d.label, d.importmap, d.file.path)
              for d in deps.to_list()
              if not any([d.importmap == t.importmap for t in test_archives])]
  dep_args.extend(["{}={}={}".format(d.label, d.importmap, d.file.path)
                   for d in test_archives])
  args.add(dep_args, before_each="-dep")

  for d in as_iterable(archive.cgo_deps):
    if d.basename.endswith('.so'):
      short_dir = d.dirname[len(d.root.path):]
      extldflags.extend(["-Wl,-rpath,$ORIGIN/" + ("../" * pkg_depth) + short_dir])

  # Process x_defs, either adding them directly to linker options, or
  # saving them to process through stamping support.
  stamp_x_defs = False
  for k, v in archive.x_defs.items():
    if v.startswith("{") and v.endswith("}"):
      args.add(["-Xstamp", "%s=%s" % (k, v[1:-1])])
      stamp_x_defs = True
    else:
      args.add(["-Xdef", "%s=%s" % (k, v)])

  # Stamping support
  stamp_inputs = []
  if stamp_x_defs or linkstamp:
    stamp_inputs = [info_file, version_file]
    args.add(stamp_inputs, before_each="-stamp")
    # linkstamp option support: read workspace status files,
    # converting "KEY value" lines to "-X $linkstamp.KEY=value" arguments
    # to the go linker.
    if linkstamp:
      args.add(["-linkstamp", linkstamp])

  args.add(extldflags, before_each = "-ld_flag")
  args.add(["-out", executable])

  args.add(["--"])
  args.add(gc_linkopts)
  args.add(go.toolchain.flags.link)
  if go.mode.strip:
    args.add(["-w"])

  if ld:
    args.add([
        "-extld", ld,
    ])

  args.add(archive.data.file)
  go.actions.run(
      inputs = sets.union(archive.libs, archive.cgo_deps,
                go.crosstool, stamp_inputs, go.stdlib.files),
      outputs = [executable],
      mnemonic = "GoLink",
      executable = go.builders.link,
      arguments = [args],
      env = go.env,
  )

def _bootstrap_link(go, archive, executable, gc_linkopts):
  """See go/toolchains.rst#link for full documentation."""

  inputs = depset([archive.data.file])
  args = ["tool", "link", "-s", "-o", executable.path]
  args.extend(gc_linkopts)
  args.append(archive.data.file.path)
  go.actions.run_shell(
      inputs = inputs + go.sdk_files + go.sdk_tools,
      outputs = [executable],
      mnemonic = "GoLink",
      command = "export GOROOT=$(pwd)/{} && export GOROOT_FINAL=GOROOT && {} {}".format(go.root, go.go.path, " ".join(args)),
  )

def _extract_extldflags(gc_linkopts, extldflags):
  """Extracts -extldflags from gc_linkopts and combines them into a single list.

  Args:
    gc_linkopts: a list of flags passed in through the gc_linkopts attributes.
      ctx.expand_make_variables should have already been applied.
    extldflags: a list of flags to be passed to the external linker.

  Return:
    A tuple containing the filtered gc_linkopts with external flags removed,
    and a combined list of external flags.
  """
  filtered_gc_linkopts = []
  is_extldflags = False
  for opt in gc_linkopts:
    if is_extldflags:
      is_extldflags = False
      extldflags.append(opt)
    elif opt == "-extldflags":
      is_extldflags = True
    else:
      filtered_gc_linkopts.append(opt)
  return filtered_gc_linkopts, extldflags
