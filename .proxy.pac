function FindProxyForURL(url, host)
{
if( (url.substring(0, 4) != "http") || isPlainHostName(host) ) return "DIRECT";
else if(
(shExpMatch(host, "*ubuntu.org.cn")) ) {
    if (url.substring(0, 5) != "https")
        return "PROXY 127.0.0.1:8080; DIRECT";
    else return "DIRECT";
    }
}
