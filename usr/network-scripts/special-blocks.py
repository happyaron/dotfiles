#!/usr/bin/env python3

import subprocess
import json
import sys

class NoAnswer(Exception):
	pass

def retrive_google_address():
	try:
		import dns.resolver
		try:
			answer = dns.resolver.resolve('_netblocks.google.com', 'TXT')

		except dns.resolver.NoAnswer:
			raise NoAnswer
		results = answer[0].strings[0].decode().replace("ip4:","").split(" ")
		results = results[2:len(results)-1]

	except(ImportError, NoAnswer):
		ret = subprocess.Popen("nslookup -q=TXT _netblocks.google.com 8.8.8.8 | grep ip4", shell=True, stdout=subprocess.PIPE)
		results = ret.stdout.readlines()[0].replace("ip4:","").split(" ")
		results = results[4:len(results)-1]

	return results


def retrive_aws_address():
	results = []
	try: 
		import requests
		ret = requests.get(r'https://ip-ranges.amazonaws.com/ip-ranges.json')
		ret = ret.json()['prefixes']
	except (ImportError, requests.exceptions.SSLError):
		ret = subprocess.Popen(["curl","-s","https://ip-ranges.amazonaws.com/ip-ranges.json"], stdout=subprocess.PIPE, universal_newlines=True)
		ret = json.load(ret.stdout)['prefixes']

	for i in ret:
		if 'us' in i['region']:
			results.append(i['ip_prefix'])
	return results

if __name__ == '__main__':
	results_google = retrive_google_address()
	results_aws = retrive_aws_address()
	file_google = open("google.txt","w")
	file_aws= open("aws.txt","w")
	for line in results_google:
		line_google="%s\n"%(line)
		file_google.write(line_google)
	file_google.close()

	for line in results_aws:
		line_aws="%s\n"%(line)
		file_aws.write(line_aws)
	file_aws.close()
