---
title: Automate and Optimize rclone in Docker
date: "2024-01-23T23:46:37.121Z"
template: "post"
draft: false
slug: "/posts/automate-and-optimize-rclone-in-docker"
category: "Homelab"
tags:
  - "Docker"
  - "rclone"
  - "Cloud Storage"
description: "This originally started as a learning experience for me to get rclone configured that I wanted to document... but as I was going through the motions I found it surprisingly difficult to find something that was plug and play. After getting rclone installed directly on a host I decided I wanted to make this as easy as possible to manage and redeploy."
socialImage: "./media/rclone.png"
---

The culmination of my experience with rclone is a completely Dockerized solution to allow auto-mounting of cloud storage. See the source [here on my GitHub](https://github.com/coanghel/rclone-docker-automount) but read on if you want to hear more about my journey.

![Rclone is a command-line program to manage files on cloud storage.](/media/rclone.png)

# Contents

1. [Introduction](#introduction)
2. [Base rclone Setup](#base-rclone-setup)
3. [Setup rclone in Docker](#setup-rclone-in-docker)
4. [Automate Mounting in Docker](#automate-mounting-in-docker)
5. [Conclusion](#conclusion)

# Introduction

Since it's inception, [rclone](https://rclone.org/) has become ubiquitous with effectively connecting cloud storage to devices running Linux, Windows, or macOS. Thanks to its cross compatibility with both hosts and cloud providers, it is seen in many homelab setups. My original goal was to get rclone configured and running on a headless server I had running Ubuntu.

# Base rclone Setup

## Configuration

Setup was pretty painless: the interactive [config generator](https://rclone.org/commands/rclone_config/) makes this easy; just follow their specific guide for [OneDrive](https://rclone.org/onedrive/), but I ran into a dead end: using the rclone tool "headless" mode. Unfortunately it seems that the size of this response causes issues in some terminals. Luckily, there's a simple work around: generate the config on the device with a web browser and then just SFTP it to your headless machine. We're in business!

## Mounting

The next step is configuring a file system mount, and having it auto-mount when the system boots. The options I found were to either add and entry to `/etc/fstab` or create systemd unit(s). I decided to set both up just to compare functionality. My conclusions are:

- Using fstab gives you no control about when the mount happens other than the optional `_netdev` parameter that delays the mount until networking is active. Using systemd units you can time other services around when the mount happens.
- Using the `x-systemd.automount` option in fstab, or generating both `.automount` and `.mount` units delays the actual mount until the mount point is accessed (e.g. ls or cd on the directory.) Make sure this is the functionality you want; it was not for me.
- If using fstab, you can include everything in a single file (a separate line for each remote,) where as using systemd units you will need a separate file (or two) for each mount point.
- Since both of these options are daemonized, you will be unable to use the `--rc` parameter (there is an open issue on rclone's repo for this). I am not sure if the `--rcd` parameter is also affected.

Below are some examples. To summarize how these function differently:

1. The remote will be mounted at boot. If you additionally add the parameter `x-systemd.automount` prior to `args2env` the mount will be delayed until you access the directory.
2. The remote will be mounted at boot.
3. The remote will be mounted when you access the directory.

### Example 1: /etc/fstab

```
OneDrive1:Data /onedrive/onedrive_1     \
rclone rw,nofail,_netdev,args2env,      \
vfs_cache_mode=full, allow_other,       \
uid=1000, gid=1000,                     \
config=/etc/rclone/rclone.conf,         \
cache_dir=/var/cache/rclone,            \
daemon-wait=600,                        \
0 0
```

After adding the above to your fstab, run `mount -av` or reboot your host.

### Example 2: onedrive-onedrive_1.mount

```
[Unit]
Description=Mount OneDrive with rclone
Wants=network-online.target docker.service
After=network-online.target docker.service

[Mount]
Type=rclone
What=OneDrive1:Data
Where=/onedrive/onedrive_1
Options=rw,nofail,_netdev,args2env,     \
vfs_cache_mode=full,allow_other,        \
uid=1000,gid=1000,                      \
config=/etc/rclone/rclone.conf,         \
cache_dir=/var/cache/rclone,            \
daemon-wait=600

[Install]
WantedBy=multi-user.target
```

After adding the above to /etc/systemd/system/onedrive-onedrive_1.mount (note that your file name needs tto match the directory in the "Where" clause of the unit) run `systemctl daemon-reload` followed by `systemctl enable onedrive-onedrive_1.mount` and then either reboot your host or run `systemctl start onedrive-onedrive_1.mount` instead.

### Example 3: onedrive-onedrive_1.automount

```
[Unit]
Description=Automount OneDrive with rclone
Wants=onedrive.mount

[Automount]
Where=/onedrive/onedrive_1

[Install]
WantedBy=multi-user.target
```

Note: this needs to be paired with onedrive-onedrive_1.mount, but instead of running `systemctl enable onedrive-onerive_1.mount` you would run `systemctl enable onedrive-onerive_1.automount`

# Setup rclone in Docker

Specifically, we'll be talking about setting up the rclone Web GUI because

- I'm a sucker for having a UI
- This will enable the powerful remote control feature of rclone

See the `rclone` service in this example [docker-compose.yml](https://github.com/coanghel/rclone-docker-automount/blob/master/docker-compose.yml) for how to get up.

The UI allows for generating rclone.config files, or adding remotes to an existing one. For remotes using OAuth 2.0 with the auth-code flow, I recommend configuring the .config on your device with a web browser and then SFTP transferring it over to the headless machine if applicable.

The compose file is pretty self explanatory, but I do want to call out a few important parts.

### Host Filesystem Mount

I mount the entire host filesystem with `/:/hostfs:rshared` but you can use a different directory such as `/mnt` if you prefer. The caveats are:

- The host directory you mount needs to contain all of the locations you plan on mounting remotes to
- If using anything other than the host root, use "shared" instead of "rshared" as the bind-propagation option e.g. `/mnt:/hostfs:shared`
- You **must** use `/hostfs` as the container mount point for the mount automation script to work.

### Serving Behind a Reverse Proxy

The docker-compose.yml configured as is will allow access from a reverse proxy that is also on the `reverse-proxy-network` Docker bridge network.

If you don't use a reverse proxy, you would want to remove this network (leave the `rclone-net` to allow communication with the auto-mount container) and instead bind the port supplied in `--rc-addr` to a port on the host.

# Automate Mounting in Docker

Here's the meat and potatoes of what I actually contributed to this whole setup! The majority of the auto-mount logic is in [rclone_initializer.py](https://github.com/coanghel/rclone-docker-automount/blob/master/rclone_initializer.py)

What is happening:

### 1. Wait for rclone

This is partially controlled by the compose file:

```
...
      depends_on:
            - rclone
...
```

However, even with this it is possible that the rclone container is running but the remote control server isn't up yet when the rclone_initializer starts. To handle this, we wait for a successful response from the remote

```
def is_rclone_ready():
    try:
        response = requests.options(f"{RCLONE_URL}/rc/noopauth", auth=AUTH)
        return response.ok
    except requests.exceptions.RequestException as e:
        logging.error(f"Error checking rclone readiness: {e}")
        return False
```

### 2. Parse User Provided Mounts

Refer to [mounts.json](https://github.com/coanghel/rclone-docker-automount/blob/master/mounts.json) for an example for how to format what you want auto-mounted. A full list of available options and their defaults (as of Jan 2024) for `mountOpt` and `vfsOpt` can be found in the [rclone Config Options](https://github.com/coanghel/rclone-docker-automount/tree/master/rclone%20Config%20Options)

### 3. Create the Mounts

The initializer will allow individual mounts to fail and continue trying the remaining. The overall process will only log a success if all mounts succeed.

```
def mount_payloads(mount_payloads):
    all_mount_success = True
    for mount_payload in mount_payloads:
        try:
            logging.info(f"Mounting {mount_payload['fs']} to {mount_payload['mountPoint']}")
            response = requests.post(f"{RCLONE_URL}/mount/mount", json=mount_payload, headers=HEADERS, auth=AUTH)
            if response.ok:
                logging.info(f"Mount successful.")
            else:
                logging.error(f"Failed to mount {mount_payload['fs']}: Status code: {response.status_code}, Response: {response.text}")
                all_mount_success = False
        except requests.exceptions.RequestException as e:
            logging.error(f"Request failed: {e}")
            all_mount_success = False
    return all_mount_success
```

### 4. Idle the Container

Docker has a few options on handling how containers restart, but unfortunately enabling any of them (so that the container starts when the host reboots) will also result in the container restarting every time the script exits, or not at all. This is partially because the base python container returns an exit code once the script completes. To summarize the options:

1. no: the container will exit when the script completes (code 0 or otherwise).

   - There will be no restart on reboot.

2. on-failure: the container will exit if all mounts are successful, otherwise it will continuously retry.

   - There will be no restart on reboot.

3. always: the container will always continuously restart and re-execute the mount process

   - There will be a restart on reboot

4. unless-stopped: similar to "always" but the cycle will end if the Docker daemon is sent a command to stop the container

   - There will be a restart on reboot unless the stop command was sent

To work around this, we include this in the [Dockerfile](https://github.com/coanghel/rclone-docker-automount/blob/master/Dockerfile):

```
CMD python ./rclone_initializer.py && tail -f /dev/null
```

The `tail -f /dev/null` will essentially cause the container to remain active but idle using minimal resources.

# Conclusion

By setting this up in Docker, we apply the benefits of containerization (ease of cross deployments, backup simplicity, and cross platform functionality) to our cloud storage mounts. We additionally can now leverage both the rclone WebGUI and the remote control for configuring mounts.

Happy Home Labbing!

<a href="https://www.buymeacoffee.com/costinanghel" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
