<?php

function generateGeminiImage(string $prompt, string $apiKey, string $model, string $outputDir = __DIR__, string $filename = 'generated_image.png'): ?string
{
    $url = "https://generativelanguage.googleapis.com/v1beta/models/{$model}:generateContent?key={$apiKey}";

    $postData = [
        'contents' => [
            [
                'parts' => [
                    ['text' => $prompt]
                ]
            ]
        ],
        'generationConfig' => [
            
            'maxOutputTokens' => 16384,
            'responseModalities' => ['TEXT', 'IMAGE'],
        ],
        'safetySettings' => [
            ['category' => 'HARM_CATEGORY_HATE_SPEECH', 'threshold' => 'BLOCK_NONE'],
            ['category' => 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold' => 'BLOCK_NONE'],
            ['category' => 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold' => 'BLOCK_NONE'],
            ['category' => 'HARM_CATEGORY_HARASSMENT', 'threshold' => 'BLOCK_NONE'],
            ['category' => 'HARM_CATEGORY_CIVIC_INTEGRITY', 'threshold' => 'BLOCK_NONE']
        ]
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 180);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json'
    ]);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($postData));

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if ($response === false) {
        throw new RuntimeException("cURL error: {$curlError}");
    }

    $responseData = json_decode($response, true);
    if ($httpCode !== 200) {
        $message = $responseData['error']['message'] ?? 'Unknown error from Gemini';
        throw new RuntimeException("Gemini API request failed: {$message}", $httpCode);
    }

    if (isset($responseData['candidates'][0]['content']['parts'])) {
        foreach ($responseData['candidates'][0]['content']['parts'] as $part) {
            if (isset($part['inlineData']['data'])) {
                $imageData = base64_decode($part['inlineData']['data']);
                $imagePath = rtrim($outputDir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $filename;
                file_put_contents($imagePath, $imageData);
                return $imagePath;
            }
        }
    }

    throw new RuntimeException("No image found in the Gemini API response: " . json_encode($responseData));
}

// Example usage:
try {
    $apiKey = 'AIzaSyDNbDOArW2h_ETmp7PdIVF9fh66oyR8NCU';
    $model = 'gemini-2.0-flash-preview-image-generation';
    $prompt = 'pakistan flag on a mountain';
    $outputPath = generateGeminiImage($prompt, $apiKey, $model);
    echo "Image saved to: {$outputPath}" . PHP_EOL;
} catch (Throwable $e) {
    echo "Error: " . $e->getMessage() . PHP_EOL;
}
