---
title: spotifyd on k3s
abbrlink: 41650
---

Deploying the [Spotifyd](https://github.com/Spotifyd/spotifyd) project to your `k3s` cluster, because you haven't ran off *all* of your friends with blathering on about how cool the `k3s` cluster at your house is.

## current deployment manifests
For those of us with no intention of doing anything other than yanking some YAML (yamlking?) and getting an easy win, this is my latest deployment manifest:

{% github_include digital-plumbers-union/megazord/master/jkcfg/shimmerjs/generated/cluster/spotifyd/spotifyd-deployment.yaml yaml %}

## how

### accessing audio device
The `spotifyd` container will need to mount two `hostPath` volumes in order to

- use your sound devices (`/dev/snd`)
- access library files for your audio backend (for ALSA, the default, `/usr/share/alsa`).

With a barebones Ubuntu server installation, I wasn't able to [access audio devices without `sudo`](https://askubuntu.com/a/279134):  

```sh
shimmerjs@bane:~$ fgrep -ie 'audio' /etc/group
audio:x:29:
```

Instead of creating a group + user for providing access to the node's audio devices without root, I granted the `spotifyd` container root privileges.  I want to be able to trash this installation and re-image the machine in the future with as few possible manual tweaks post-imaging.  This installation does not face the public internet, so the risk in running a privileged container on my node is lower than it normally would be.  

If you choose to create such a group + user, you can provide the [specific group + user name via the `Pod`'s security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod).

### hostnetwork
Without providing `hostNetwork: true` on the `PodSpec`, `spotifyd` was unable to establish a connection on my local network to listen for Spotify connect sessions, which makes sense.  [This is also called out in the Docker container documentation](https://hub.docker.com/r/ggoussard/spotifyd):

>The --net host is to allow local network discovery, without it Spotify Connect uses the cloud to link the devices.

### figuring out which audio device its supposed to use
If your node doesn't have multiple audio devices, `spotifyd` may figure out what to do without using the `--device` flag.  I am attempting to use [USB AudioEngine bookshelf speakers](https://audioengineusa.com/shop/poweredspeakers/a2-plus-desktop-speakers/), and the computer I am using as my node had onboard sound devices in a previous life.  As a result, `spotifyd` was unable to find the correct device automatically.

I was able to determine the correct device name to pass to `spotifyd` using `aplay`:

```bash
shimmerjs@bane:~$ sudo aplay -L

...

default:CARD=A2
    Audioengine 2+, USB Audio
    Default Audio Device

...

```

I have no idea why `spotifyd` wasn't able to find this device, even with root privileges, since it is clearly labeled as the `Default Audio Device`.  I didn't care to explore further, as I was too busy listening to the sweet sounds of success.

### scheduling
Unless you have a magic virtual audio appliance that is available to all of your worker nodes, you'll need to provide a node selector that limits scheduling `spotifyd` pods to your node with the audio device.