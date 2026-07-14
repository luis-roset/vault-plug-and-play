FROM docker.mirror.hashicorp.services/python:3.7

RUN apt update -qq

RUN apt install -y python3-pip

RUN pip install --upgrade pip setuptools

RUN pip install splunk-appinspect
