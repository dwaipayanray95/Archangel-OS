# Get a server on DigitalOcean

DigitalOcean has a beginner-friendly control panel with clear screens. A small server costs about 6 US dollars a month and is billed by the hour. (Prices change. Check the price shown on the create screen.)

> Website screens change often. If a button has moved, look for the same words nearby.

**You will end with:** a server's public IP address, the username `root`, a private key file, and UDP port 51820 open.

---

## 1. Create an account

1. Go to <https://www.digitalocean.com/> and click **Sign up**.
2. Verify your email and add a payment method (a card or PayPal).
3. DigitalOcean calls servers **Droplets**.

## 2. Make an SSH key

DigitalOcean needs your **public** key. If you don't have a key yet, see [SSH keys in plain words](../getting-started.md#ssh-keys-in-plain-words) and run `ssh-keygen -t ed25519`. You upload the `.pub` file. Keep the private file (without `.pub`) safe. You give that one to the Archangel app.

## 3. Create the droplet

1. Click **Create** (top right) → **Droplets**.
2. **Region:** pick one near you.
3. **Image:** **Ubuntu 24.04 (LTS) x64** (22.04 also works).
4. **Size:** **Basic** → **Regular** (SSD). Choose one with at least **1 GB** of memory; **2 GB** is more comfortable.
5. **Authentication:** choose **SSH Key** → **New SSH Key**, paste your **public** key, give it a name, and add it. Make sure it is ticked.
6. Give the droplet a name, and click **Create Droplet**.
7. Wait about a minute until it shows a green dot and an IP address.

## 4. Find the public IP and username

- The **IPv4 address** is shown in the droplet list and at the top of the droplet's page.
- The username is **`root`**.

## 5. Open UDP 51820

DigitalOcean has **Cloud Firewalls**. If you haven't created one, all ports are open and you can skip this step. If you have one attached, add a rule.

1. In the left menu, open **Networking** → **Firewalls** → **Create Firewall** (or click an existing one).
2. Under **Inbound Rules**, make sure these exist:

| Type | Protocol | Port range | Sources |
|---|---|---|---|
| SSH | TCP | `22` | All IPv4 |
| **Custom** | **UDP** | **`51820`** | **All IPv4** |

3. Under **Apply to Droplets**, type your droplet's name and select it.
4. Click **Create Firewall** / **Save**.

Optional, only if you will use Caddy web addresses: add HTTP (TCP `80`) and HTTPS (TCP `443`) too.

## 6. Run the setup wizard

Back to [Getting started, step 4](../getting-started.md#4-run-the-setup-wizard). Use:

- **Server address:** your public IP
- **Username:** `root`
- **SSH key:** your private key

If something fails, see [Troubleshooting](../troubleshooting.md).

## Good to know

- **Switching off still bills.** A powered-off droplet still costs money. **Destroy** it to stop paying.
- **Backups.** DigitalOcean offers paid backups and snapshots.
