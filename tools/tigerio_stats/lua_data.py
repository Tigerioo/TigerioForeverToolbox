"""Parse the data-only subset emitted by WoW SavedVariables, never execute Lua."""
import re

MAX_DEPTH = 100
MAX_SIZE = 128 * 1024 * 1024
IDENT = re.compile(r'[A-Za-z_][A-Za-z_0-9]*')
NUMBER = re.compile(r'-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')


class ParseError(ValueError):
    pass


class Parser:
    def __init__(self, text):
        if len(text) > MAX_SIZE:
            raise ParseError("SavedVariables exceeds size limit")
        self.text, self.pos = text, 0

    def space(self):
        s = self.text
        while self.pos < len(s):
            if s[self.pos].isspace():
                self.pos += 1
            elif s.startswith('--', self.pos):
                end = s.find('\n', self.pos)
                self.pos = len(s) if end < 0 else end + 1
            else:
                return

    def match(self, token):
        self.space()
        if self.text.startswith(token, self.pos):
            self.pos += len(token)
            return True
        return False

    def expect(self, token):
        if not self.match(token):
            raise ParseError(f"expected {token!r} at {self.pos}")

    def name(self):
        self.space()
        found = IDENT.match(self.text, self.pos)
        if not found:
            raise ParseError(f"expected identifier at {self.pos}")
        self.pos = found.end()
        return found.group()

    def string(self):
        s = self.text
        quote = s[self.pos]
        self.pos += 1
        out = bytearray()
        escapes = {'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9, 'v': 11,
                   '\\': 92, '"': 34, "'": 39}
        while self.pos < len(s):
            c = s[self.pos]
            self.pos += 1
            if c == quote:
                try:
                    return out.decode('utf-8')
                except UnicodeDecodeError as exc:
                    raise ParseError('invalid UTF-8 in string') from exc
            if c != '\\':
                out.extend(c.encode('utf-8'))
                continue
            if self.pos >= len(s):
                break
            c = s[self.pos]
            self.pos += 1
            if c in escapes:
                out.append(escapes[c])
            elif c.isascii() and c.isdigit():
                digits = c
                while len(digits) < 3 and self.pos < len(s) and s[self.pos].isascii() and s[self.pos].isdigit():
                    digits += s[self.pos]
                    self.pos += 1
                number = int(digits)
                if number > 255:
                    raise ParseError('invalid decimal escape')
                out.append(number)
            elif c == '\n':
                out.append(10)
            elif c == '\r':
                if self.pos < len(s) and s[self.pos] == '\n':
                    self.pos += 1
                out.append(10)
            else:
                raise ParseError(f'unsupported escape at {self.pos}')
        raise ParseError('unterminated string')

    def value(self, depth=0):
        if depth > MAX_DEPTH:
            raise ParseError('maximum nesting exceeded')
        self.space()
        if self.pos >= len(self.text):
            raise ParseError('unexpected end')
        c = self.text[self.pos]
        if c in "\"'":
            return self.string()
        if c == '{':
            return self.table(depth + 1)
        found = NUMBER.match(self.text, self.pos)
        if found:
            raw = found.group()
            self.pos = found.end()
            value = float(raw) if any(x in raw for x in '.eE') else int(raw)
            if isinstance(value, float) and not __import__('math').isfinite(value):
                raise ParseError('non-finite number')
            return value
        name = self.name()
        if name == 'true': return True
        if name == 'false': return False
        if name == 'nil': return None
        raise ParseError(f'unsupported value {name!r}')

    def table(self, depth):
        self.expect('{')
        result, index = {}, 1
        while not self.match('}'):
            self.space()
            if self.match('['):
                key = self.value(depth)
                self.expect(']')
                self.expect('=')
            else:
                start = self.pos
                try:
                    candidate = self.name()
                except ParseError:
                    candidate = None
                if candidate is not None and self.match('='):
                    key = candidate
                else:
                    self.pos = start
                    key, index = index, index + 1
            if not isinstance(key, (str, int, float, bool)) or key is None:
                raise ParseError('invalid table key')
            result[key] = self.value(depth)
            if self.match('}'):
                break
            if not self.match(',') and not self.match(';'):
                raise ParseError(f'expected table separator at {self.pos}')
        return result


def parse(text):
    parser = Parser(text.lstrip('\ufeff'))
    if parser.name() != 'TigerioForeverToolboxDB':
        raise ParseError('unexpected saved variable name')
    parser.expect('=')
    result = parser.value()
    parser.space()
    if parser.pos != len(parser.text) or not isinstance(result, dict):
        raise ParseError('unexpected trailing data or root value')
    return result


def sequence(value):
    if not isinstance(value, dict):
        return []
    output, index = [], 1
    while index in value:
        output.append(value[index])
        index += 1
    return output
