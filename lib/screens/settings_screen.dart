import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.person),
            title: Text('Edit Profile'),
            onTap: () {
              // TODO: Implement edit profile functionality
            },
          ),
          ListTile(
            leading: Icon(Icons.notifications),
            title: Text('Notifications'),
            onTap: () {
              // TODO: Implement notifications settings
            },
          ),
          ListTile(
            leading: Icon(Icons.color_lens),
            title: Text('App Theme'),
            onTap: () {
              // TODO: Implement theme settings
            },
          ),
          ListTile(
            leading: Icon(Icons.language),
            title: Text('Language'),
            onTap: () {
              // TODO: Implement language settings
            },
          ),
          SwitchListTile(
            title: Text('Celebrity Comparison'),
            value: true, // TODO: Implement actual state management
            onChanged: (bool value) {
              // TODO: Implement toggle functionality
            },
          ),
        ],
      ),
    );
  }
}