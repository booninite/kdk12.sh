workspace(
  name = "kdk12_sh",
  # tells bazel that node_modules/ is managed by the package manager:
  # https://bazelbuild.github.io/rules_nodejs/install.html#using-bazel-managed-dependencies
  managed_directories = {
    "@npm": ["node_modules"]
  }
)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# load rules_node
http_archive(
    name = "build_bazel_rules_nodejs",
    sha256 = "d0c4bb8b902c1658f42eb5563809c70a06e46015d64057d25560b0eb4bdc9007",
    urls = ["https://github.com/bazelbuild/rules_nodejs/releases/download/1.5.0/rules_nodejs-1.5.0.tar.gz"],
)

# we're going to need our trusty dewalt tool bag, filled to the brim
# with goodies
local_repository(
  name = "dpu_dewalt_toolbag",
  path = "../dev/dpu/toolbag"
)

# hexo dependencies, targets, packages, etc
local_repository(
  name = "dpu_hexo_wrenches",
  path = "../dev/dpu/hexo-wrenches"
)

# hexo theme
local_repository(
  name = "dpu_hexo_theme_pipes",
  path = "../dev/dpu/hexo-theme-pipes"
)

# set up bazel-managed dependencies:
# https://bazelbuild.github.io/rules_nodejs/install.html#using-bazel-managed-dependencies
# using `yarn_install` without calling `node_repositories` will cause
# rules_node to call `node_repositories` with the default settings, 
# which is to default to the latest version of yarn/node that were released
# when the version of rules_node we are using was released
load("@build_bazel_rules_nodejs//:index.bzl", "yarn_install")
yarn_install(
  name = "npm",
  package_json = "//:package.json",
  yarn_lock = "//:yarn.lock"
)

# set up dependencies we instaled via npm, if any
load("@npm//:install_bazel_dependencies.bzl", "install_bazel_dependencies")
install_bazel_dependencies()

# Set up TypeScript toolchain
load("@npm_bazel_typescript//:index.bzl", "ts_setup_workspace")
ts_setup_workspace()