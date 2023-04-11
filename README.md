Communicate with openai's streaming chat completion api by piping conversations to stdin and getting output from stdout.

To continue the conversation, you just feed the output back into the program.

This design makes it easy to write output to disk, make edits if desired, and resume conversations at your leisure.

## Installation
`go install github.com/jpe90/orq`

## Usage

```
$ orq [options]
```

### Flags

```
-model [string]
	Chat model to use for completions. Defaults to gpt-3.5-turbo.

-key [string]

	OpenAI API key.

-system [string]

	System level instructions to guide the model's behavior.
```

### Usage Notes

#### Command line
Write to stdout and save to a file: `echo "how run a command and discard stderr?" | orq | tee discard_stderr.txt`

#### Acme
Pipe selections to `orq.`

#### Emacs
Emacs support is available in `utils/orq.el`

