"""Structured operational logs without request data or exception messages."""
import datetime as dt
import json
import logging
import re
import time
import traceback
import uuid


EVENTS = frozenset(('authentication_required', 'permission_denied', 'write_conflict',
                    'upload_too_large', 'server_error', 'request_rejected'))
METHODS = frozenset(('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'))


def identifier(value):
    return re.sub(r'[^a-zA-Z0-9_.<>-]', '_', str(value))[:120]


class PrivateFormatter(logging.Formatter):
    """Never stringify msg/args, requests, exception values or arbitrary extras.

    Regex replacement of secrets cannot cover opaque tokens or provider errors.
    Keep only code locations and a small schema of operational fields instead.
    """

    def format(self, record):
        payload = {
            'time': dt.datetime.fromtimestamp(record.created, dt.timezone.utc).isoformat(),
            'level': record.levelname,
            'logger': identifier(record.name),
            'event': getattr(record, 'log_event', None)
            if getattr(record, 'log_event', None) in EVENTS else 'application_log',
            'source': identifier(record.module) + ':' + str(record.lineno),
        }
        status = getattr(record, 'status_code', None)
        if type(status) is int and 100 <= status <= 599:
            payload['status'] = status
        request = getattr(record, 'request', None)
        if request is not None:
            if request.method in METHODS:
                payload['method'] = request.method
            # This is the URLconf pattern, never the expanded URL or query.
            match = getattr(request, 'resolver_match', None)
            if match is not None and isinstance(match.route, str):
                payload['route'] = match.route[:240]
            request_id = getattr(request, '_linesight_request_id', '')
            if isinstance(request_id, str) and re.fullmatch(r'[0-9a-f]{32}', request_id):
                payload['request_id'] = request_id
        elapsed = getattr(record, 'elapsed_ms', None)
        if type(elapsed) is int and 0 <= elapsed < 86400000:
            payload['elapsed_ms'] = elapsed
        if record.exc_info and record.exc_info[0]:
            payload['exception_type'] = identifier(record.exc_info[0].__name__)
            payload['frames'] = [
                {'function': identifier(frame.name), 'line': frame.lineno}
                for frame in traceback.extract_tb(record.exc_info[2])[-8:]
            ]
        return json.dumps(payload, ensure_ascii=True, separators=(',', ':'))


class RequestDiagnosticsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        self.logger = logging.getLogger('linesight.http')

    def __call__(self, request):
        request._linesight_request_id = uuid.uuid4().hex
        start = time.monotonic()
        response = self.get_response(request)
        response['X-Request-ID'] = request._linesight_request_id
        status = response.status_code
        if status >= 400:
            event = {401: 'authentication_required', 403: 'permission_denied',
                     409: 'write_conflict', 413: 'upload_too_large'}.get(
                         status, 'server_error' if status >= 500 else 'request_rejected')
            self.logger.log(logging.ERROR if status >= 500 else logging.WARNING,
                'request failed', extra={'log_event': event, 'request': request,
                    'status_code': status, 'elapsed_ms': int((time.monotonic()-start)*1000)})
        return response
