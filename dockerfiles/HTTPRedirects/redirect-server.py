#!/usr/bin/env python3

# HTTP Redirects - Part of bee2 https://github.com/sumdog/bee2
# https://penguindreams.org - Sumit Khanna<sumit@penguindreams.org>
# License: GNU GPLv3

import http.server
import socket
import socketserver
from os import environ as env


class HTTPServerV6(http.server.HTTPServer):
    address_family = socket.AF_INET6


class RedirectHandler(http.server.SimpleHTTPRequestHandler):

    def redirect_to(self, domain):
        for r in eval(env['REDIRECTS']):
            (d_from, d_to) = r.split(':')
            if d_from == domain:
                return d_to
        return None

    def do_GET(self):
        self.redirect()

    def do_POST(self):
        self.redirect()

    def do_PUT(self):
        self.redirect()

    def do_DELETE(self):
        self.redirect()

    def redirect(self):
        to = self.redirect_to(self.headers['Host'])
        if to is not None:
            self.send_response(301)
            self.send_header('Location', 'https://{}'.format(to))
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write('Not Found'.encode('utf-8'))

if __name__ == '__main__':

    handler = RedirectHandler
    httpd = HTTPServerV6(('::', 8080), handler)
    httpd.serve_forever()
