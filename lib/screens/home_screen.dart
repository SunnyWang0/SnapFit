import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Body Fat Progress'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Progress',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Expanded(
              child: BodyFatChart(),
            ),
          ],
        ),
      ),
    );
  }
}

class BodyFatChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: 40,
        lineBarsData: [
          LineChartBarData(
            spots: [
              FlSpot(0, 30),
              FlSpot(1, 28),
              FlSpot(2, 26),
              FlSpot(3, 25),
              FlSpot(4, 23),
              FlSpot(5, 22),
              FlSpot(6, 20),
            ],
            isCurved: true,
            colors: [Colors.blue],
            barWidth: 3,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(show: true, colors: [Colors.blue.withOpacity(0.3)]),
          ),
        ],
      ),
    );
  }
}