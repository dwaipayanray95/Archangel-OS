# Get a free server on Oracle Cloud

Oracle Cloud has an "Always Free" tier. You can get a small server that stays free. The catch: signing up needs a card for verification, and free servers in popular regions are sometimes "full". This guide shows how to deal with that.

> Website screens change often. If a button has moved, look for the same words nearby. The ideas stay the same.

**You will end with:** a server's public IP address, the username `ubuntu`, a private key file, and UDP port 51820 open.

---

## 1. Create an account

1. Go to <https://www.oracle.com/cloud/free/> and click **Start for free**.
2. Fill in your details and verify your email.
3. Choose your **home region**, the data centre location. **You cannot change it later**, and free servers only exist in your home region. Pick one near you. Popular regions are more often out of capacity (see step 3).
4. Add a card for verification. Free tier resources should not be charged, but Oracle may place a small temporary hold.

## 2. Make an SSH key

Oracle can generate one for you in the next step (easiest). If you prefer your own, see [SSH keys in plain words](../getting-started.md#ssh-keys-in-plain-words).

## 3. Create the server

1. In the Oracle Cloud Console, open the menu (top left) → **Compute** → **Instances** → **Create instance**.
2. **Name:** anything, like `archangel`.
3. **Image and shape** → **Edit**:
   - **Image:** click **Change image** → **Ubuntu** → **Canonical Ubuntu 24.04** (the plain one, not "Minimal").
   - **Shape:** click **Change shape**.
     - **Ampere** → **VM.Standard.A1.Flex** (ARM, Always Free eligible). Start with **1 OCPU and 6 GB memory**. Smaller requests succeed more often.
     - Or **Specialty and previous generation** → **VM.Standard.E2.1.Micro** (Intel/AMD, Always Free, 1 GB memory). It always has capacity, but only 1 GB of memory is small. Archangel runs on it, but keep your apps light.
4. **Networking:** keep the defaults. Make sure **Assign a public IPv4 address** is on.
5. **Add SSH keys:** choose **Generate a key pair for me** and click **Save private key**. Keep the downloaded file safe (for example in a password manager). You cannot download it again. Or choose **Paste public keys** to use your own.
6. Click **Create**. Wait until the instance says **Running**.

### "Out of capacity for shape VM.Standard.A1.Flex"

This is common. Free ARM servers are popular. What to try:

- Try again later. Early morning and late night in the region's time zone often work. It can take hours, sometimes days.
- Ask for less: **1 OCPU and 6 GB**.
- If your region has more than one **availability domain**, try each one (it is a setting on the same screen).
- Use the **VM.Standard.E2.1.Micro** shape instead. It is less powerful, but it is rarely full.
- Be careful with third-party "capacity hunter" scripts. They need your account keys.

The free ARM allowance is up to 4 OCPUs and 24 GB in total, but your account or region may allow less.

## 4. Find the public IP and username

1. Open your instance's page (Compute → Instances → click its name).
2. Copy the **Public IP address**.
3. The username is **`ubuntu`** for Ubuntu images.

## 5. Open UDP 51820

Oracle has its own firewall around your network, called a **security list**. It blocks everything by default.

1. On your instance's page, under **Primary VNIC**, click the **Subnet** link.
2. Click the **Security** tab and open the **Default Security List** for your VCN.
3. Click **Add Ingress Rules** (or **Security rules** → **Add ingress rules**) and fill in:

| Field | Value |
|---|---|
| Stateless | leave unticked |
| Source Type | CIDR |
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | **UDP** |
| Source Port Range | leave empty |
| Destination Port Range | `51820` |

4. Click **Add Ingress Rules**.

TCP port 22 (SSH) is already open in the default list.

> The server also has its own firewall. The Archangel setup wizard takes care of that one. You only need to do the Oracle part.

## 6. Run the setup wizard

Back to [Getting started, step 4](../getting-started.md#4-run-the-setup-wizard). Use:

- **Server address:** your public IP
- **Username:** `ubuntu`
- **SSH key:** the private key you saved

If something fails, see [Troubleshooting](../troubleshooting.md).

## Good to know

- **Idle servers may be reclaimed.** Oracle can stop Always Free instances that sit nearly unused for a long time. Using the server now and then helps.
- **Backups.** The free tier is not a backup service. Keep copies of anything important.
