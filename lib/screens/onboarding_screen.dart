import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  List<Widget> _pages = [
    _OnboardingPage(
      title: "Welcome",
      description: "Let's set up your profile",
      child: _NameInputWidget(),
    ),
    _OnboardingPage(
      title: "Personal Information",
      description: "Tell us about yourself",
      child: _AgeGenderWidget(),
    ),
    _OnboardingPage(
      title: "Body Measurements",
      description: "Enter your height and weight",
      child: _HeightWeightWidget(),
    ),
    _OnboardingPage(
      title: "Fitness Goals",
      description: "What's your activity level and goal?",
      child: _ActivityGoalWidget(),
    ),
    _OnboardingPage(
      title: "Your Progress",
      description: "See how you'll improve over time",
      child: _ProgressGraphWidget(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _currentPage = page;
              });
            },
            children: _pages,
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => _buildDot(index),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      height: 10,
      width: 10,
      margin: EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _currentPage == index ? Colors.blue : Colors.grey,
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _OnboardingPage({
    Key? key,
    required this.title,
    required this.description,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 40),
          child,
        ],
      ),
    );
  }
}

// Implement _NameInputWidget, _AgeGenderWidget, _HeightWeightWidget, _ActivityGoalWidget, and _ProgressGraphWidget