This repository contains artifacts for configuring Splunk or a Splunk App to
assist in monitoring and visualizing HashiCorp products' metrics and/or
logs.

Installation
------------

To install the Splunk app locally, assuming your Splunk is installed in
/opt/splunk:

    cp -r app/ /opt/splunk/etc/apps/vault

Packaging
---------

To package the app for SplunkBase, run:

    make build-package

It will produce a tarball in the pkg directory. 

You can then use the following make targets to validate the package and run AppInspect against it:

    make validate-package

    make appinspect-package

    make appinspect-package-cloud

Releasing
---------

To release a new version of the app see [Vault Splunk Release Process](https://docs.google.com/document/d/1dtoM_sg-Mtlyy-OkS-vX2UP-hXlkEOlVtuSyPCX-iCY/edit?usp=sharing).