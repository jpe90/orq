package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

// https://github.com/openai/openai-cookbook/blob/main/examples/How_to_stream_completions.ipynb
type Chunk struct {
	Choices []struct {
		Delta struct {
			Content string `json:"content"`
		} `json:"delta"`
		FinishReason string `json:"finish_reason"`
		Index        int    `json:"index"`
	} `json:"choices"`
	Created int64  `json:"created"`
	ID      string `json:"id"`
	Model   string `json:"model"`
	Object  string `json:"object"`
}

type ChatCompletionMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatCompletionRequest struct {
	Model    string                  `json:"model"`
	Messages []ChatCompletionMessage `json:"messages"`
	Stream   bool                    `json:"stream"`
}

var (
	key    = flag.String("key", "", "Your OpenAI API key.")
	system = flag.String("system", "", "System level instructions to guide the model's behavior.")
	model  = flag.String("model", "gpt-3.5-turbo", "Chat model to use for completions")
)

func parseInput(input string) []ChatCompletionMessage {
	lines := strings.Split(input, "\n")
	var messages []ChatCompletionMessage
	role := "user"
	content := ""

	for _, line := range lines {
		switch line {
		case "---BEGIN AI RESPONSE":
			messages = append(messages, ChatCompletionMessage{Role: role, Content: content})
			content = ""
			role = "assistant"
		case "---END AI RESPONSE":
			messages = append(messages, ChatCompletionMessage{Role: role, Content: content})
			content = ""
			role = "user"
		default:
			content += line + "\n"
		}
	}
	messages = append(messages, ChatCompletionMessage{Role: role, Content: content})
	return messages
}

func main() {
	flag.Parse()
	if *key == "" {
		*key = os.Getenv("OPENAI_API_KEY")
	}
	if *key == "" {
		log.Fatal("No API key provided")
	}
	ctx := context.Background()
	var input string
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		input += scanner.Text() + "\n"
	}

	var messages []ChatCompletionMessage
	if *system != "" {
		messages = append(messages, ChatCompletionMessage{
			Role:    "system",
			Content: *system,
		})
	}
	parsedInput := parseInput(input)
	fmt.Print(input)
	fmt.Println("---BEGIN AI RESPONSE")
	messages = append(messages, parsedInput...)

	completionRequest := ChatCompletionRequest{
		Model:    *model,
		Messages: messages,
		Stream:   true,
	}

	reqBytes, err := json.Marshal(completionRequest)
	if err != nil {
		println("marshal err:: ", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(reqBytes))

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Connection", "keep-alive")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", *key))
	httpClient := http.Client{}
	resp, err := httpClient.Do(req)

	reader := bufio.NewReader(resp.Body)
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err == io.EOF {
				fmt.Println("End of stream")
			} else {
				println("Error reading from stream: %!(NOVERB)v", err)
			}
			return
		}

		var header = []byte("data: ")
		line = bytes.TrimSpace(line)

		if !bytes.HasPrefix(line, header) {
			continue
		}

		line = bytes.TrimPrefix(line, header)
		if string(line) == "[DONE]" {
			fmt.Println("\n---END AI RESPONSE")
			return
		}

		var completionResponse Chunk
		err = json.Unmarshal(line, &completionResponse)

		if err != nil {
			println("unmarshal err:: ", err)
		}

		if completionResponse.Choices[0].FinishReason == "stop" {
			continue
		}

		fmt.Print(completionResponse.Choices[0].Delta.Content)
	}
}
