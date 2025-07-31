#!/usr/bin/env python3
"""
Simple maintenance server for HAProxy fallback
Provides basic health checks and maintenance responses
"""

import http.server
import socketserver
import json
import os
from datetime import datetime

PORT = 8080

class MaintenanceHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_health_response()
        elif self.path.startswith('/api/health'):
            self.send_api_health_response()
        elif self.path.startswith('/app/health'):
            self.send_app_health_response()
        elif self.path.startswith('/admin/health'):
            self.send_admin_health_response()
        elif self.path.startswith('/demo/health'):
            self.send_demo_health_response()
        else:
            self.send_maintenance_response()
    
    def send_health_response(self):
        """Standard health check response"""
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'healthy')
    
    def send_api_health_response(self):
        """API-specific health check response"""
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {
            "status": "ok",
            "timestamp": datetime.utcnow().isoformat(),
            "service": "maintenance-mode"
        }
        self.wfile.write(json.dumps(response).encode())
    
    def send_app_health_response(self):
        """Application health check response"""
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'application_ready')
    
    def send_admin_health_response(self):
        """Admin health check response"""
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'admin_healthy')
    
    def send_demo_health_response(self):
        """Demo health check response"""
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'healthy')
    
    def send_maintenance_response(self):
        """Maintenance mode response"""
        self.send_response(503)
        self.send_header('Content-type', 'text/html')
        self.send_header('Retry-After', '300')
        self.end_headers()
        
        html_response = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Service Temporarily Unavailable</title>
            <style>
                body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
                .container { max-width: 600px; margin: 0 auto; }
                .status { color: #e74c3c; font-size: 24px; margin-bottom: 20px; }
                .message { color: #7f8c8d; font-size: 16px; line-height: 1.6; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="status">Service Temporarily Unavailable</div>
                <div class="message">
                    The service you requested is currently undergoing maintenance or is temporarily unavailable.
                    <br><br>
                    Please try again in a few minutes.
                    <br><br>
                    If this problem persists, please contact the system administrator.
                </div>
            </div>
        </body>
        </html>
        """
        self.wfile.write(html_response.encode())
    
    def log_message(self, format, *args):
        """Override to provide better logging"""
        timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] {format % args}")

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), MaintenanceHandler) as httpd:
        print(f"Maintenance server starting on port {PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nMaintenance server shutting down...")
            httpd.shutdown()