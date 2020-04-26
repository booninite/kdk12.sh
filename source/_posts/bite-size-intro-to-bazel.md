---
title: a bite size introduction to bazel
abbrlink: 3501
---

## building, testing, and publishing containers with `rules_docker`

Unless you're already familiar with Java, C++, or mobile development, the [official Bazel tutorials](https://docs.bazel.build/versions/master/getting-started.html#tutorials) aren't going to be extremely useful.  Beyond that, the official docs throw you into the deep end to sort out your own mental model of how this pile of new abstractions play with each other.

This example makes a basic change to an existing open source project with a container hosted on DockerHub&copy;, tests it using [GoogleContainerTools/container-structure-test](https://github.com/GoogleContainerTools/container-structure-test), and publishes it on DockerHub&copy; under [my own repository](https://hub.docker.com/r/shimmerjs/nfs-alpine-server).

Example source:

[digital-plumbers-union/containers@60920ed263485c5da06a019dff3936b714d8e957](https://github.com/digital-plumbers-union/containers/tree/60920ed263485c5da06a019dff3936b714d8e957)

## setup

The [official Bazel installation docs are fine](https://docs.bazel.build/versions/master/install.html), but since you are a progressive-minded individual, you will want to use [Bazelisk](https://github.com/bazelbuild/bazelisk).  I recommend following their advice and either aliasing it to `bazel` or installing it to `/usr/local/bin/bazel`.

Configure it for our repository:

```sh
echo "2.2.0" > .bazelversion
```

Don't commit Bazel output:

```sh
echo 'bazel-*' > .gitignore
```

Create an empty `BUILD.bazel` in workspace root since there is no need for one at the moment.

## wire up dependencies in `WORKSPACE`

We will need:

- [`rules_docker`](https://github.com/bazelbuild/rules_docker)
- [`rules_pkg`](https://github.com/bazelbuild/rules_pkg) to create tars of the files I want to add to containers at specific paths.
- Container images for both ARM ad AMD.

```python
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# setup rules_docker

http_archive(
    name = "io_bazel_rules_docker",
    sha256 = "dc97fccceacd4c6be14e800b2a00693d5e8d07f69ee187babfd04a80a9f8e250",
    strip_prefix = "rules_docker-0.14.1",
    urls = ["https://github.com/bazelbuild/rules_docker/releases/download/v0.14.1/rules_docker-v0.14.1.tar.gz"],
)

load(
    "@io_bazel_rules_docker//repositories:repositories.bzl",
    container_repositories = "repositories",
)

container_repositories()

# This is NOT needed when going through the language lang_image
# "repositories" function(s).
load("@io_bazel_rules_docker//repositories:deps.bzl", container_deps = "deps")

container_deps()

# load container_pull so we can pull in base
# images we depend on 
load(
    "@io_bazel_rules_docker//container:container.bzl",
    "container_pull",
)

# setup rules_pkg
load("@rules_pkg//:deps.bzl", "rules_pkg_dependencies")

rules_pkg_dependencies()

# pull our containers
container_pull(
    name = "nfs_server_arm_base",
    digest = "sha256:fa1f27cefb54f26df59f4fb8efce02ab0e45f1fe34cfb818dadbf8ddac6b2bc3",
    registry = "index.docker.io",
    repository = "itsthenetwork/nfs-server-alpine",
)

container_pull(
    name = "nfs_server_amd_base",
    digest = "sha256:7fa99ae65c23c5af87dd4300e543a86b119ed15ba61422444207efc7abd0ba20",
    registry = "index.docker.io",
    repository = "itsthenetwork/nfs-server-alpine",
)
```

## extend itsthenetwork/nfs-server-alpine to enable `crossmnt`

I want to make a simple change by adding `crossmnt` to the `exports` file that configures the mounts that the NFS server will expose:

```
{{SHARED_DIRECTORY}} {{PERMITTED}}({{READ_ONLY}},fsid=0,{{SYNC}},no_subtree_check,no_auth_nlm,insecure,no_root_squash,crossmnt)
```

```sh
mkdir containers/
touch containers/BUILD
```

I need to create these customized images for both ARM and AMD so that I can run the servers on a mixed-arch `k3s` cluster without too much fuss, so in `containers/BUILD`, I define them as an array I can iterate on when defining targets:

```python
architectures = [
    "amd",
    "arm",
]
```

Before using `container_image`, I need to package up the modified `exports` file in such a way that when it is extracted into the container, it ends up at the right location with the right permissions, which we do with `pkg_tar`:

```python
pkg_tar(
    name = "exports-file",
    srcs = ["exports"],
    extension = "tar.gz",
    mode = "644",
    # we want the final resting place to be /etc/exports
    package_dir = "/etc",
    # have to set strip_prefix = "." because of this bug:
    # https://github.com/bazelbuild/rules_pkg/issues/82
    strip_prefix = ".",
)
```

Now I can iterate over the array I declared above to create targets for building the containers (via `container_image`):

```python
[container_image(
    name = a,
    base = "@nfs_server_" + a + "_base//image",
    tars = [":exports-file"],
) for a in architectures]
```

When `containers/BUILD` is evaluated, I will have two targets named `//containers:arm` and `//containers/amd` and each will use the correct base image since I am computing the string value based on the architecture.

## testing via `container_test`

```python
[container_test(
    name = a + "_test",
    configs = [":tests.yaml"],
    # previously created targets were simply the
    # archicture name, so we can now reference them
    # as we would a non-generated target
    image = ":" + a,
) for a in architectures]
```

The tests themselves are simple container structure tests and not particularly relevant:

{% github_include digital-plumbers-union/containers/60920ed263485c5da06a019dff3936b714d8e957/nfs-server-alpine/tests.yaml yaml %}


## publishing them individually via `container_push`

```python
[container_push(
    name = "push_" + a + "_container",
    format = "Docker",
    image = ":" + a,
    registry = "index.docker.io",
    repository = "shimmerjs/nfs-alpine-server",
    tag = a,
) for a in architectures]
```

Now I can `bazel query //...` and see:

```sh
//nfs-server-alpine:push_arm_container
//nfs-server-alpine:push_amd_container
//nfs-server-alpine:arm_test
//nfs-server-alpine:arm_test.image
//nfs-server-alpine:arm
//nfs-server-alpine:amd_test
//nfs-server-alpine:amd_test.image
//nfs-server-alpine:amd
//nfs-server-alpine:exports-file
Loading: 1 packages loaded
```

At this point I have accomplished all that I set out to do functionallity.

# eat a snickers

Still hungry?

## setting up a single push target for both containers

I use `container_bundle` to create a single target for both images:

```python
container_bundle(
    name = "bundle",
    images = {image_name(a): ":" + a for a in architectures},
)
```

There is an alternative `container_push` implementation at `@io_bazel_rules_docker//contrib:push-all.bzl`, and since it has the same name, I alias it to `push_all` when I load it:

```python
load("@io_bazel_rules_docker//contrib:push-all.bzl", push_all = "container_push")

# push our bundle of containers
push_all(
    name = "push_images",
    bundle = ":bundle",
    format = "Docker",
)
```

Now my entire `containers/BUILD` file is:

{% github_include digital-plumbers-union/containers/60920ed263485c5da06a019dff3936b714d8e957/nfs-server-alpine/BUILD %}

## adding `buildifier` to lint and reformat your Bazel files

[Follow the stupid long dependencies for `buildifier`](https://github.com/bazelbuild/buildtools/tree/master/buildifier#setup-and-usage-via-bazel).

When done, my `WORKSPACE` was:

{% github_include digital-plumbers-union/containers/60920ed263485c5da06a019dff3936b714d8e957/WORKSPACE %}

## using bazel query to make sure you always push containers in CI

`container_test` and `container_image` are rules that produce test and build targets, so they will be executed when you run `bazel test //...` or `bazel build //...`.  

`container_push` is different.  If you `bazel build //containers:push_arm_container`, it will produce the image digest:

```sh
cat bazel-bin/nfs-server-alpine/push_arm_container.digest                               1 ↵
sha256:0fedfd2a4402ead0085bd5bf7c217e3fa027d98e1a10aec726febfe7e0a4a7e5%
```

Which is pretty neat, but doesn't actually push your container.  You will need to `bazel run` `container_push` targets in CI to publish containers.  To avoid hardcoding a set of targets, you can use `bazel query` to produce the list of targets that are of kind `container_push` and `bazel run` each one:

```sh
#!/usr/bin/env bash
PUSH_TARGETS=`bazel query 'kind(container_push, //...)'`
for target in $PUSH_TARGETS; do "bazel run $target"; done
```