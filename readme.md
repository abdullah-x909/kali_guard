<h1>Anonymity Guard</h1>

<p><strong>Anonymity Guard</strong> is a fully automated Bash script for enhancing anonymity on Kali Linux. 
It configures Tor for automatic IP rotation using <code>NEWNYM</code>, rotates MAC addresses on physical interfaces, 
provides DNS leak protection, applies a firewall-based kill switch, disables IPv6, generates random hostnames, 
and continuously monitors Tor to enforce safe network behavior.</p>

<p>Designed for privacy-focused users and penetration testers. 
Use responsibly and legally—this tool is intended for <strong>ethical purposes only</strong>.</p>

<hr>

<h2>Features</h2>
<ul>
  <li><strong>One-command installation</strong> (via curl).</li>
  <li><strong>Tor IP Rotation</strong> using NEWNYM for frequent circuit renewal.</li>
  <li><strong>Automatic MAC Changer</strong> on physical interfaces (excludes loopback, docker, veth, etc.).</li>
  <li><strong>Transparent Tor Proxy</strong> routing all traffic through Tor.</li>
  <li><strong>DNS Leak Protection</strong> via Tor’s DNSPort and immutable <code>resolv.conf</code>.</li>
  <li><strong>Firewall Kill Switch</strong> using iptables—blocks all non-Tor traffic.</li>
  <li><strong>IPv6 Disable</strong> to prevent leaks.</li>
  <li><strong>Random Hostname Generation</strong> on each startup.</li>
  <li><strong>Tor Monitoring</strong>—auto-lockdown if Tor stops.</li>
</ul>

<h3>Additional Enhancements</h3>
<ul>
  <li>Idempotent Tor configuration.</li>
  <li>Safe interface detection logic.</li>
  <li>Custom rotation interval and interface support.</li>
  <li>Persistent iptables rules.</li>
  <li>Logging to <code>/var/log/anonymity-guard.log</code>.</li>
  <li>Graceful shutdown with <code>--stop</code> to revert all changes.</li>
</ul>

<hr>

<h2>Requirements</h2>
<ul>
  <li>Kali Linux (recent version)</li>
  <li>Root privileges</li>
  <li>Internet connection for first-time setup</li>
</ul>

<hr>

<h2>Installation</h2>

<h3>One-command install and run:</h3>

<pre><code>curl -sSL https://raw.githubusercontent.com/abdullah-x909/anonymity-guard/main/anonymity-guard.sh | sudo bash
</code></pre>

<p>This installs dependencies, configures Tor, sets firewall rules, and starts the guard automatically.</p>

<hr>

<h3>Install as a systemd service (optional)</h3>

<ol>
  <li>Download the script to <code>/usr/local/bin/anonymity-guard.sh</code></li>
  <li>Make it executable:</li>
</ol>

<pre><code>sudo chmod +x /usr/local/bin/anonymity-guard.sh
</code></pre>

<ol start="3">
  <li>Create the service file <code>/etc/systemd/system/anonymity-guard.service</code>:</li>
</ol>

<pre><code>[Unit]
Description=Anonymity Guard
After=network.target tor.service

[Service]
ExecStart=/usr/local/bin/anonymity-guard.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
</code></pre>

<ol start="4">
  <li>Enable and start the service:</li>
</ol>

<pre><code>sudo systemctl enable --now anonymity-guard
</code></pre>

<hr>

<h2>Usage</h2>

<p>Run directly:</p>

<pre><code>sudo ./anonymity-guard.sh [options]
</code></pre>

<h3>Options</h3>
<ul>
  <li><code>--interval &lt;seconds&gt;</code>: Set rotation interval (default: 300)</li>
  <li><code>--interface &lt;name&gt;</code>: Use a specific interface</li>
  <li><code>--stop</code>: Revert all changes and exit</li>
  <li><code>--log</code>: View the live log file</li>
</ul>

<hr>

<h2>Verification</h2>

<ul>
  <li>Check Tor status: <a href="https://check.torproject.org/">https://check.torproject.org/</a></li>
  <li>Check public IP: <code>curl ifconfig.me</code></li>
  <li>DNS leak test: <a href="https://dnsleaktest.com/">https://dnsleaktest.com/</a></li>
</ul>

<hr>

<h2>Uninstallation</h2>

<p>Revert changes:</p>

<pre><code>sudo ./anonymity-guard.sh --stop
</code></pre>

<p>Remove optional packages:</p>

<pre><code>sudo apt remove tor macchanger net-tools netcat-traditional iptables-persistent
</code></pre>

<p>Delete script & service:</p>

<pre><code>sudo rm -f /usr/local/bin/anonymity-guard.sh
sudo rm -f /etc/systemd/system/anonymity-guard.service
</code></pre>

<hr>

<h2>Warnings</h2>

<ul>
  <li>All traffic is forced through Tor—connections may slow.</li>
  <li>MAC rotation may reset WiFi temporarily; wired is more stable.</li>
  <li>Do not use for illegal activities.</li>
  <li>Tor cannot guarantee anonymity if you log into personal accounts.</li>
  <li>Reboot requires re-running unless using systemd.</li>
</ul>

<hr>

<h2>Contributing</h2>

<p>Pull requests are welcome. Ideas include:</p>
<ul>
  <li>Integrating torsocks for app-level routing</li>
  <li>VPN fallback mode</li>
</ul>

<hr>

<h2>License</h2>
<p>MIT License — see <code>LICENSE</code> file.</p>
