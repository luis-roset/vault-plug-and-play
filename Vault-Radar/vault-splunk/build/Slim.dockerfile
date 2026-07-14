FROM docker.mirror.hashicorp.services/python:3.7

RUN apt-get update -qq

RUN apt-get install -y python3-pip

RUN pip install --upgrade pip setuptools

RUN pip install semantic_version

RUN pip install splunk-packaging-toolkit
