pkill -9 vault
rm -f pidfile
rm -f agent-policy.hcl
rm -f CA_cert.crt
rm -f logs/*		
rm -f /etc/vault/*
rm -f app/app.properties
