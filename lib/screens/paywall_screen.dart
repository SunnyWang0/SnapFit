import 'package:flutter/material.dart';

class PaywallScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Unlock Full Access',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              Text(
                'Reach your fitness goals with accurate tracking and AI body composition analysis',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 40),
              ElevatedButton(
                child: Text('Unlock for \$4.99'),
                onPressed: () {
                  // TODO: Implement payment processing
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}