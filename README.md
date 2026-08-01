# NoMail - Smart Email Client

A revolutionary Flutter-based email client that transforms Gmail into an intelligent personal assistant. NoMail uses AI to analyze your emails and provide actionable insights, making email management effortless and insightful.

## 🌟 Features

### Core Email Functionality
- **Full Gmail Integration**: Complete access to read, compose, reply, and manage emails
- **Smart Inbox**: AI-powered email categorization and importance scoring
- **Advanced Search**: Natural language search powered by AI
- **Rich Compose**: Templates, quick replies, scheduled sending, and formatting tools
- **Thread Management**: Conversation view with full thread support
- **Label Management**: Create and manage custom labels
- **Swipe Actions**: Archive and delete with intuitive gestures

### AI-Powered Insights
- **Amazon Order Tracking**: Automatic detection and tracking of orders, deliveries, and packages
- **Subscription Management**: Identifies all subscriptions with monthly/yearly cost projections
- **Bill Tracking**: Monitors bills, due dates, and payment status
- **Smart Summaries**: AI-generated summaries for long emails
- **Keyword Extraction**: Automatic identification of important topics
- **Importance Scoring**: AI determines email priority based on content and context

### Financial Intelligence
- **Spending Analysis**: Comprehensive breakdown of expenses
- **Monthly/Yearly Projections**: Forecast future spending based on current subscriptions
- **Bill Reminders**: Never miss a payment deadline
- **Order Analytics**: Track shopping patterns and delivery schedules

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.0 or higher)
- Dart SDK
- Google Cloud Console account for Gmail API
- Claude API key or OpenAI API key

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/hmail.git
cd hmail
```

2. Install dependencies:
```bash
flutter pub get
```

3. Configure environment variables:
Create a `.env` file in the root directory:
```env
CLAUDE_API_KEY=your_claude_api_key
OPENAI_API_KEY=your_openai_api_key
GOOGLE_CLIENT_ID=your_google_oauth_client_id
```

4. Set up Gmail API:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing
   - Enable Gmail API
   - Create OAuth 2.0 credentials
   - Add authorized redirect URIs for your app

### Running the App

#### Mobile (iOS/Android):
```bash
flutter run
```

#### Web:
```bash
flutter run -d chrome
```

#### Build for Production:

iOS:
```bash
flutter build ios --release
```

Android:
```bash
flutter build apk --release
```

Web:
```bash
flutter build web --release
```

## 🧪 Testing

Run the test suite:
```bash
flutter test
```

Run with coverage:
```bash
flutter test --coverage
```

## 📱 Platform Support

- ✅ iOS
- ✅ Android  
- ✅ Web
- 🔄 macOS (coming soon)
- 🔄 Windows (coming soon)
- 🔄 Linux (coming soon)

## 🏗️ Architecture

NoMail follows a clean architecture pattern with:
- **Provider** for state management
- **Repository pattern** for data access
- **Service layer** for business logic
- **Model-View-ViewModel (MVVM)** pattern

### Project Structure:
```
lib/
├── models/          # Data models
├── providers/       # State management
├── services/        # Business logic & API calls
├── screens/         # UI screens
├── widgets/         # Reusable UI components
└── main.dart        # App entry point
```

## 🔒 Security

- OAuth 2.0 authentication with Google
- No password storage - uses Google's secure authentication
- API keys stored in environment variables
- Secure token refresh mechanism
- Optional biometric authentication (on supported devices)

## 🎨 Customization

NoMail supports:
- Light and dark themes
- Custom color schemes
- Adjustable text sizes
- Multiple language support (i18n ready)

## 📈 Performance

- Lazy loading for email lists
- Image caching for avatars
- Efficient state management
- Optimized for 60fps scrolling
- Background email sync

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Google Gmail API for email access
- Anthropic Claude & OpenAI for AI capabilities
- Flutter team for the amazing framework
- All contributors and users

## 📞 Support

For support, email support@nomail.app or open an issue on GitHub.

## 🚦 Roadmap

- [ ] Calendar integration
- [ ] Contact management
- [ ] Email encryption
- [ ] Offline mode
- [ ] Multi-account support
- [ ] Desktop apps (macOS, Windows, Linux)
- [ ] Browser extension
- [ ] Smart notifications
- [ ] Voice commands
- [ ] Email analytics dashboard

## 💡 Why NoMail?

Traditional email clients show you emails. NoMail understands them. It's not just an inbox; it's your personal email intelligence system that:
- Saves time with AI-powered insights
- Prevents missed payments and deliveries
- Tracks spending automatically
- Prioritizes what matters most
- Makes email management effortless

Transform your Gmail experience today with NoMail!