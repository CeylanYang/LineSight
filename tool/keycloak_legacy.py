"""Trusted offline conversion; never match an incoming login by username."""
import base64
import json


def argon2_credential(encoded):
    marker, kind, version, parameters, salt, digest = encoded.split('$')
    if marker != 'argon2' or kind not in ('argon2id', 'argon2i', 'argon2d') or version != 'v=19':
        raise ValueError('Unsupported legacy password representation')
    params = dict(item.split('=') for item in parameters.split(','))
    decode = lambda value: base64.b64decode(value + '=' * (-len(value) % 4), validate=True)
    salt64 = base64.b64encode(decode(salt)).decode()
    digest64 = base64.b64encode(decode(digest)).decode()
    additional = {'type': [kind.removeprefix('argon2')], 'version': ['1.3'],
        'memory': [str(int(params['m']))], 'parallelism': [str(int(params['p']))],
        'hashLength': [str(len(decode(digest)))]}
    return {'type': 'password', 'temporary': False,
        'credentialData': json.dumps({'algorithm': 'argon2', 'hashIterations': int(params['t']),
                                     'additionalParameters': additional}),
        'secretData': json.dumps({'value': digest64, 'salt': salt64})}
