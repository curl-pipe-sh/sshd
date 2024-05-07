# sshd

This script fetches the SSH public key of a given GitHub user (default: `pschmitt`)
and adds it to the `authorized_keys` file of the current user + root.

Finally it installs/starts OpenSSH server and starts sshd.

## Usage

```shell
curl -L curl-pipe.sh/sshd | bash -s -- --github-user YOUR_USER
```

```shell
wget -O- curl-pipe.sh/sshd | GITHUB_USER=YOUR_USER sh
```
