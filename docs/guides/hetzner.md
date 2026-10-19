# Get a server on Hetzner

Hetzner is simple, fast and cheap. A small server costs roughly 4 to 5 euros a month and is billed by the hour, so you can delete it any time and stop paying. (Prices change. Check the price shown on the create screen.)

> Website screens change often. If a button has moved, look for the same words nearby.

**You will end with:** a server's public IP address, the username `root`, a private key file, and UDP port 51820 open.

---

## 1. Create an account

1. Go to <https://www.hetzner.com/cloud> and click **Sign Up**.
2. Verify your email. Hetzner may ask for an ID check or a payment method before it lets you create servers.
3. In the Cloud Console (<https://console.hetzner.cloud/>), create a **Project** (any name, like `archangel`).

## 2. Make an SSH key

Hetzner needs your **public** key. If you don't have a key yet, see [SSH keys in plain words](../getting-started.md#ssh-keys-in-plain-words) and run `ssh-keygen -t ed25519`. You will upload the `.pub` file in the next step. Keep the private file (without `.pub`) safe. You will give that one to the Archangel app.

## 3. Create the server

1. In your project, click **Add Server**.
2. **Location:** pick one near you.
3. **Image:** **Ubuntu 24.04** (22.04 also works).
4. **Type:** a small **Shared vCPU** type is plenty. Pick one with at least 2 GB of memory if you can. Intel/AMD (x86) and Arm (Ampere) types both work with Archangel.
5. **Networking:** keep **Public IPv4** on.
6. **SSH keys:** click **Add SSH key**, paste your **public** key (the contents of the `.pub` file) and save. Make sure it is ticked.
7. **Firewalls:** pick the firewall you will create in step 5, or come back and attach it after.
8. Name it, and click **Create & Buy now**.

## 4. Find the public IP and username

- The **IPv4 address** is shown in the servers list and on the server's page.
- The username is **`root`**. (Hetzner Ubuntu images sign you in as root, not `ubuntu`.)

## 5. Open UDP 51820

Hetzner has a **Cloud Firewall**. If you don't use one, all ports are open already and you can skip this step. If you do use one, add a rule.

1. In your project, open **Firewalls** in the left menu, then **Create Firewall** (or open an existing one).
2. Under **Inbound rules**, make sure these exist:

| Protocol | Port | Source |
|---|---|---|
| TCP | `22` | Any IPv4 (`0.0.0.0/0`) |
| **UDP** | **`51820`** | Any IPv4 (`0.0.0.0/0`) |

3. Under **Apply to**, select your server (or its label).
4. Click **Create Firewall** / **Save**.

Optional, only if you will use Caddy web addresses: add TCP `80` and TCP `443` too.

## 6. Run the setup wizard

Back to [Getting started, step 4](../getting-started.md#4-run-the-setup-wizard). Use:

- **Server address:** your public IP
- **Username:** `root`
- **SSH key:** your private key

If something fails, see [Troubleshooting](../troubleshooting.md).

## Good to know

- **Stopping isn't free.** A switched-off server still reserves its space, so Hetzner still bills it. Delete the server to stop paying.
- **Backups.** Hetzner has paid backups and snapshots, if you want them.
