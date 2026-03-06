# BlueSpeak Privacy Policy (Draft)

This draft describes how BlueSpeak currently handles permissions, text, and account data. Review it with legal counsel before publishing it as your final public privacy policy.

## What BlueSpeak does

BlueSpeak is a macOS app that lets users:

- dictate text
- translate dictated text
- rewrite selected text with voice instructions

To do that, BlueSpeak needs access to speech recognition, microphone input, and certain macOS accessibility permissions.

## Permissions BlueSpeak requests

BlueSpeak may request access to:

- Speech Recognition: used to turn spoken audio into text
- Microphone: used to record audio while dictating
- Accessibility: used to read selected text and insert rewritten text into other apps
- Input Monitoring: used to detect global keyboard shortcuts such as the configured trigger key

BlueSpeak only uses these permissions to provide its core features.

## Data processed by Apple

BlueSpeak uses Apple's speech recognition APIs on macOS. Depending on macOS behavior and the user's system configuration, spoken audio and related speech data may be sent to Apple to process speech recognition requests.

## Data sent to the BlueSpeak backend

When a user dictates, translates, or rewrites text with AI enabled, BlueSpeak sends text content and request metadata to the configured BlueSpeak backend.

This can include:

- dictated text
- selected text (for rewrite)
- rewrite instructions spoken by the user
- selected language, style, and interpretation settings
- limited app context used to improve formatting

The backend is used to format text, translate text, and run rewrite instructions.

## Data sent to OpenAI

If AI features are enabled, the BlueSpeak backend sends relevant text content to OpenAI to generate:

- polished dictation output
- translated output
- rewritten output

BlueSpeak is designed so that AI requests send only the text needed to complete the user's action.

## Authentication and account data

BlueSpeak uses Supabase for authentication.

Supabase may process:

- email address
- password
- session tokens
- optional signup metadata such as name, country, and marketing preference

BlueSpeak stores the signed-in user's email address and active session information locally on the user's Mac so the user can remain signed in between launches.

## Data stored locally on the user's Mac

BlueSpeak stores some data locally using macOS app storage. This may include:

- dictation history
- selected language and translation settings
- selected writing style and interpretation level
- selected microphone
- configured shortcut trigger key
- backend URL
- active session token and refresh token
- signed-in email address and display name

This local data is stored to make the app usable between launches.

## User controls

Users can control local data from the app, including:

- clearing dictation history
- signing out and clearing the local session
- changing permissions in macOS System Settings

If a user signs out, BlueSpeak removes the local active session used for authenticated backend requests.

## Data sharing

BlueSpeak does not use dictation content for advertising.

BlueSpeak shares data only with service providers needed to operate the product, including:

- Apple (speech recognition, depending on macOS behavior)
- the configured BlueSpeak backend host
- OpenAI (AI text generation)
- Supabase (authentication)

## Security

BlueSpeak uses authenticated backend requests for signed-in users. However, users should still avoid dictating highly sensitive information unless they understand how their configured backend and third-party providers process data.

## Contact

For privacy questions, data handling requests, or support, provide a dedicated contact address such as:

- privacy@bluespeak.app
