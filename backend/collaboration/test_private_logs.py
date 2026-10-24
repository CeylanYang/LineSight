import io
import json
import logging
import sys
from contextlib import contextmanager

from django.http import HttpResponse
from django.test import Client, RequestFactory, SimpleTestCase, override_settings
from django.urls import path, resolve

from linesight.privacy_log import PrivateFormatter, RequestDiagnosticsMiddleware


CANARY = 'PRIVATE-password-token-nfc-invite-email-62813'


def crash(request, username):
    raise RuntimeError(CANARY)


urlpatterns = [path('members/<str:username>/', crash)]


@contextmanager
def private_capture(*names):
    output = io.StringIO()
    handler = logging.StreamHandler(output)
    handler.setFormatter(PrivateFormatter())
    loggers = [logging.getLogger(name) for name in names]
    saved = [(logger.handlers[:], logger.level, logger.propagate) for logger in loggers]
    try:
        for logger in loggers:
            logger.handlers = [handler]; logger.setLevel(logging.DEBUG); logger.propagate = False
        yield output
    finally:
        for logger, (handlers, level, propagate) in zip(loggers, saved):
            logger.handlers = handlers; logger.setLevel(level); logger.propagate = propagate


class PrivateLogsTests(SimpleTestCase):
    def test_exception_chain_message_args_and_extras_never_stringified(self):
        class ForbiddenString:
            def __str__(self):
                raise AssertionError('Private value stringified')
        try:
            try: raise ValueError(CANARY)
            except ValueError: raise RuntimeError(CANARY)
        except RuntimeError:
            record = logging.LogRecord('django.request', logging.ERROR, __file__, 40,
                ForbiddenString(), (ForbiddenString(),), sys.exc_info())
        record.stack_info = CANARY
        record.token = CANARY
        record.exc_text = CANARY
        text = PrivateFormatter().format(record)
        self.assertNotIn(CANARY, text)
        result = json.loads(text)
        self.assertEqual(result['exception_type'], 'RuntimeError')
        self.assertTrue(result['frames'])

    @override_settings(ROOT_URLCONF=__name__)
    def test_http_failures_keep_status_and_route_without_path_headers_or_body(self):
        for status in (400, 401, 403, 404, 409, 413, 500, 503):
            with self.subTest(status=status), private_capture('linesight.http') as output:
                request = RequestFactory().post('/members/'+CANARY+'/?code='+CANARY,
                    {'password':CANARY,'refresh_token':CANARY,'invite_code':CANARY},
                    HTTP_AUTHORIZATION='Bearer '+CANARY, HTTP_COOKIE='session='+CANARY,
                    HTTP_X_REQUEST_ID=CANARY)
                request.resolver_match = resolve(request.path)
                response = RequestDiagnosticsMiddleware(lambda r: HttpResponse(status=status))(request)
                text = output.getvalue(); self.assertNotIn(CANARY, text)
                result = json.loads(text)
                self.assertEqual(result['status'], status)
                self.assertEqual(result['route'], 'members/<str:username>/')
                self.assertEqual(result['request_id'], response['X-Request-ID'])

    @override_settings(ROOT_URLCONF=__name__, DEBUG=False, ALLOWED_HOSTS=['testserver'],
        MIDDLEWARE=['linesight.privacy_log.RequestDiagnosticsMiddleware'])
    def test_django_unhandled_exception_does_not_leak_into_operational_logs(self):
        with private_capture('django.request', 'linesight.http') as output:
            response = Client(raise_request_exception=False).get('/members/'+CANARY+'/?token='+CANARY)
        self.assertEqual(response.status_code, 500)
        self.assertNotIn(CANARY, output.getvalue())
        records = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertTrue(any(r.get('exception_type')=='RuntimeError' for r in records))
        self.assertTrue(any(r.get('event')=='server_error' for r in records))

    def test_success_does_not_create_request_log_or_reuse_untrusted_request_id(self):
        request = RequestFactory().get('/', HTTP_X_REQUEST_ID=CANARY)
        with private_capture('linesight.http') as output:
            response = RequestDiagnosticsMiddleware(lambda r: HttpResponse())(request)
        self.assertEqual(output.getvalue(), '')
        self.assertRegex(response['X-Request-ID'], r'^[0-9a-f]{32}$')
