# third-order-takeover
🛠 Dependencies

Before running the script, make sure the following tools are installed and available in your $PATH:
- subfinder
- naabu
- httpx
- getJS
- unfurl
- nuclei
- html-tool

You can install them with:
```
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/003random/getJS/v2@latest
go install -v github.com/tomnomnom/unfurl@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
Manual Install https://github.com/tomnomnom/hacks/tree/master/html-tool
Manual Install https://github.com/reewardius/cspgrabber
```
🚀 Usage

You can run the script with either a single domain or a file containing domains:
```bash
sudo bash general_takeover_with_cspgrabber_last.sh -d vulnweb.com        # For a single root domain
sudo bash general_takeover_with_cspgrabber_last.sh -d testphp.vulnweb.com -ds  # For a single subdomain
sudo bash general_takeover_with_cspgrabber_last.sh -f root.txt           # For multiple root domains
```
