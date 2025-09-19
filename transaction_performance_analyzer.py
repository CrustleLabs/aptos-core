#!/usr/bin/env python3

"""
Aptos Transaction Performance Analyzer
Comprehensive analysis tool for transaction timing and performance metrics
"""

import json
import re
import sys
import argparse
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
from collections import defaultdict, namedtuple
from pathlib import Path

# Performance stages in order
STAGES_ORDER = [
    'mempool_received',
    'mempool_validation', 
    'mempool_added',
    'payload_pull',
    'proposal_generation',
    'proposal_broadcast',
    'proposal_received',
    'block_prepare',
    'transaction_execution',
    'block_execution',
    'vote_generation',
    'vote_broadcast',
    'vote_aggregation',
    'quorum_cert_creation',
    'block_commit',
    'chain_committed'
]

TimingRecord = namedtuple('TimingRecord', ['timestamp', 'tx_hash', 'stage', 'duration', 'metadata'])

class TransactionPerformanceAnalyzer:
    def __init__(self, log_directory):
        self.log_directory = Path(log_directory)
        self.timing_records = []
        self.transactions = defaultdict(dict)
        self.stage_statistics = defaultdict(list)
        
    def parse_log_files(self):
        """Parse all log files to extract performance data"""
        print("Parsing log files...")
        
        log_files = list(self.log_directory.glob("**/*.log")) + \
                   list(self.log_directory.glob("**/*.txt"))
        
        for log_file in log_files:
            self._parse_single_log_file(log_file)
        
        print(f"Parsed {len(self.timing_records)} timing records for {len(self.transactions)} transactions")
    
    def _parse_single_log_file(self, log_file):
        """Parse a single log file for performance records"""
        try:
            with open(log_file, 'r') as f:
                for line_num, line in enumerate(f, 1):
                    if 'PERF_TRACK:' in line:
                        try:
                            record = self._parse_perf_line(line)
                            if record:
                                self.timing_records.append(record)
                                self._update_transaction_data(record)
                        except Exception as e:
                            print(f"Warning: Failed to parse line {line_num} in {log_file}: {e}")
        except Exception as e:
            print(f"Warning: Failed to read {log_file}: {e}")
    
    def _parse_perf_line(self, line):
        """Parse a single performance tracking line"""
        # Pattern: PERF_TRACK: <tx_hash> - <stage> at <duration> (total: <total_duration>)
        pattern = r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+).*PERF_TRACK:\s*([a-f0-9]+)\s*-\s*(\w+)\s*at\s*([\d.]+\w+)\s*\(total:\s*([\d.]+\w+)\)'
        
        match = re.search(pattern, line)
        if match:
            timestamp_str, tx_hash, stage, stage_duration, total_duration = match.groups()
            
            # Parse timestamp
            timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            
            # Parse durations (convert to milliseconds)
            stage_dur_ms = self._parse_duration(stage_duration)
            total_dur_ms = self._parse_duration(total_duration)
            
            # Extract metadata if present
            metadata = {}
            metadata_match = re.search(r'\{([^}]+)\}', line)
            if metadata_match:
                metadata_str = metadata_match.group(1)
                for item in metadata_str.split(','):
                    if ':' in item:
                        key, value = item.split(':', 1)
                        metadata[key.strip()] = value.strip()
            
            return TimingRecord(
                timestamp=timestamp,
                tx_hash=tx_hash,
                stage=stage,
                duration=stage_dur_ms,
                metadata=metadata
            )
        
        return None
    
    def _parse_duration(self, duration_str):
        """Parse duration string and convert to milliseconds"""
        if duration_str.endswith('ms'):
            return float(duration_str[:-2])
        elif duration_str.endswith('us'):
            return float(duration_str[:-2]) / 1000
        elif duration_str.endswith('s'):
            return float(duration_str[:-1]) * 1000
        elif duration_str.endswith('ns'):
            return float(duration_str[:-2]) / 1000000
        else:
            # Assume milliseconds
            return float(duration_str)
    
    def _update_transaction_data(self, record):
        """Update transaction data with timing record"""
        tx_hash = record.tx_hash
        stage = record.stage
        
        self.transactions[tx_hash][stage] = {
            'timestamp': record.timestamp,
            'duration': record.duration,
            'metadata': record.metadata
        }
        
        self.stage_statistics[stage].append(record.duration)
    
    def calculate_statistics(self):
        """Calculate comprehensive performance statistics"""
        stats = {}
        
        # Calculate stage statistics
        for stage, durations in self.stage_statistics.items():
            if durations:
                stats[stage] = {
                    'count': len(durations),
                    'min': min(durations),
                    'max': max(durations),
                    'avg': sum(durations) / len(durations),
                    'p50': self._percentile(durations, 50),
                    'p95': self._percentile(durations, 95),
                    'p99': self._percentile(durations, 99)
                }
        
        # Calculate end-to-end statistics
        e2e_times = []
        complete_transactions = 0
        
        for tx_hash, stages in self.transactions.items():
            if 'mempool_received' in stages and 'chain_committed' in stages:
                start_time = stages['mempool_received']['timestamp']
                end_time = stages['chain_committed']['timestamp']
                e2e_duration = (end_time - start_time).total_seconds() * 1000  # Convert to ms
                e2e_times.append(e2e_duration)
                complete_transactions += 1
        
        if e2e_times:
            stats['end_to_end'] = {
                'count': len(e2e_times),
                'min': min(e2e_times),
                'max': max(e2e_times),
                'avg': sum(e2e_times) / len(e2e_times),
                'p50': self._percentile(e2e_times, 50),
                'p95': self._percentile(e2e_times, 95),
                'p99': self._percentile(e2e_times, 99)
            }
        
        stats['summary'] = {
            'total_transactions': len(self.transactions),
            'complete_transactions': complete_transactions,
            'completion_rate': complete_transactions / len(self.transactions) if self.transactions else 0
        }
        
        return stats
    
    def _percentile(self, data, percentile):
        """Calculate percentile of data"""
        sorted_data = sorted(data)
        index = int(len(sorted_data) * percentile / 100)
        return sorted_data[min(index, len(sorted_data) - 1)]
    
    def generate_visualizations(self, output_dir):
        """Generate performance visualization charts"""
        output_dir = Path(output_dir)
        output_dir.mkdir(exist_ok=True)
        
        # Set style
        plt.style.use('seaborn-v0_8')
        sns.set_palette("husl")
        
        # 1. Stage duration box plot
        stage_data = []
        stage_labels = []
        
        for stage in STAGES_ORDER:
            if stage in self.stage_statistics and self.stage_statistics[stage]:
                stage_data.append(self.stage_statistics[stage])
                stage_labels.append(stage.replace('_', '\n'))
        
        if stage_data:
            plt.figure(figsize=(15, 8))
            plt.boxplot(stage_data, labels=stage_labels)
            plt.title('Transaction Processing Stage Duration Distribution')
            plt.ylabel('Duration (ms)')
            plt.xticks(rotation=45, ha='right')
            plt.tight_layout()
            plt.savefig(output_dir / 'stage_duration_boxplot.png', dpi=300, bbox_inches='tight')
            plt.close()
        
        # 2. End-to-end latency histogram
        e2e_times = []
        for tx_hash, stages in self.transactions.items():
            if 'mempool_received' in stages and 'chain_committed' in stages:
                start_time = stages['mempool_received']['timestamp']
                end_time = stages['chain_committed']['timestamp']
                e2e_duration = (end_time - start_time).total_seconds() * 1000
                e2e_times.append(e2e_duration)
        
        if e2e_times:
            plt.figure(figsize=(10, 6))
            plt.hist(e2e_times, bins=20, alpha=0.7, edgecolor='black')
            plt.title('End-to-End Transaction Latency Distribution')
            plt.xlabel('Latency (ms)')
            plt.ylabel('Number of Transactions')
            plt.axvline(x=sum(e2e_times)/len(e2e_times), color='red', linestyle='--', label=f'Average: {sum(e2e_times)/len(e2e_times):.1f}ms')
            plt.legend()
            plt.tight_layout()
            plt.savefig(output_dir / 'e2e_latency_histogram.png', dpi=300, bbox_inches='tight')
            plt.close()
        
        # 3. Transaction timeline
        if len(self.transactions) > 0:
            plt.figure(figsize=(15, 8))
            
            for i, (tx_hash, stages) in enumerate(list(self.transactions.items())[:10]):  # Show first 10 transactions
                stage_times = []
                stage_names = []
                
                if 'mempool_received' in stages:
                    base_time = stages['mempool_received']['timestamp']
                    
                    for stage in STAGES_ORDER:
                        if stage in stages:
                            relative_time = (stages[stage]['timestamp'] - base_time).total_seconds() * 1000
                            stage_times.append(relative_time)
                            stage_names.append(stage)
                    
                    plt.plot(stage_times, [i] * len(stage_times), 'o-', label=f'TX {tx_hash[:8]}')
            
            plt.title('Transaction Processing Timeline')
            plt.xlabel('Time from Mempool Receipt (ms)')
            plt.ylabel('Transaction ID')
            plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
            plt.tight_layout()
            plt.savefig(output_dir / 'transaction_timeline.png', dpi=300, bbox_inches='tight')
            plt.close()
        
        print(f"✓ Visualizations generated in: {output_dir}")
    
    def export_data(self, output_file):
        """Export performance data to JSON for further analysis"""
        data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'total_transactions': len(self.transactions),
                'total_records': len(self.timing_records)
            },
            'transactions': {},
            'stage_statistics': {}
        }
        
        # Export transaction data
        for tx_hash, stages in self.transactions.items():
            data['transactions'][tx_hash] = {}
            for stage, stage_data in stages.items():
                data['transactions'][tx_hash][stage] = {
                    'timestamp': stage_data['timestamp'].isoformat(),
                    'duration': stage_data['duration'],
                    'metadata': stage_data['metadata']
                }
        
        # Export stage statistics
        stats = self.calculate_statistics()
        data['stage_statistics'] = stats
        
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"✓ Performance data exported to: {output_file}")
    
    def print_report(self):
        """Print comprehensive performance report"""
        stats = self.calculate_statistics()
        
        print("\n" + "="*60)
        print("APTOS TRANSACTION PERFORMANCE ANALYSIS REPORT")
        print("="*60)
        
        if 'summary' in stats:
            summary = stats['summary']
            print(f"\nSUMMARY:")
            print(f"  Total Transactions: {summary['total_transactions']}")
            print(f"  Complete Transactions: {summary['complete_transactions']}")
            print(f"  Completion Rate: {summary['completion_rate']:.1%}")
        
        if 'end_to_end' in stats:
            e2e = stats['end_to_end']
            print(f"\nEND-TO-END PERFORMANCE:")
            print(f"  Count: {e2e['count']}")
            print(f"  Average: {e2e['avg']:.2f}ms")
            print(f"  Min: {e2e['min']:.2f}ms")
            print(f"  Max: {e2e['max']:.2f}ms")
            print(f"  P50: {e2e['p50']:.2f}ms")
            print(f"  P95: {e2e['p95']:.2f}ms")
            print(f"  P99: {e2e['p99']:.2f}ms")
        
        print(f"\nSTAGE-BY-STAGE PERFORMANCE:")
        print(f"{'Stage':<25} {'Count':<8} {'Avg':<10} {'P95':<10} {'P99':<10}")
        print("-" * 70)
        
        for stage in STAGES_ORDER:
            if stage in stats and stage != 'end_to_end' and stage != 'summary':
                stage_stats = stats[stage]
                print(f"{stage:<25} {stage_stats['count']:<8} "
                      f"{stage_stats['avg']:<10.2f} {stage_stats['p95']:<10.2f} {stage_stats['p99']:<10.2f}")
        
        # Performance analysis
        print(f"\nPERFORMANCE ANALYSIS:")
        self._analyze_performance_issues(stats)
        
        print("\n" + "="*60)
    
    def _analyze_performance_issues(self, stats):
        """Analyze performance data for potential issues"""
        issues = []
        recommendations = []
        
        # Check end-to-end latency
        if 'end_to_end' in stats:
            e2e_avg = stats['end_to_end']['avg']
            if e2e_avg > 1000:  # > 1 second
                issues.append(f"High end-to-end latency: {e2e_avg:.2f}ms")
                recommendations.append("Investigate consensus and execution bottlenecks")
            elif e2e_avg > 500:  # > 500ms
                issues.append(f"Moderate end-to-end latency: {e2e_avg:.2f}ms")
        
        # Check individual stage performance
        slow_stages = []
        for stage in ['transaction_execution', 'block_execution', 'vote_generation']:
            if stage in stats:
                avg_duration = stats[stage]['avg']
                p95_duration = stats[stage]['p95']
                
                if stage == 'transaction_execution' and avg_duration > 10:
                    slow_stages.append(f"{stage}: {avg_duration:.2f}ms avg")
                elif stage == 'block_execution' and avg_duration > 100:
                    slow_stages.append(f"{stage}: {avg_duration:.2f}ms avg")
                elif stage == 'vote_generation' and avg_duration > 5:
                    slow_stages.append(f"{stage}: {avg_duration:.2f}ms avg")
        
        if slow_stages:
            issues.append("Slow execution stages detected:")
            for stage in slow_stages:
                issues.append(f"  - {stage}")
        
        # Print issues and recommendations
        if issues:
            print("  Issues Detected:")
            for issue in issues:
                print(f"    ⚠ {issue}")
        else:
            print("  ✓ No performance issues detected")
        
        if recommendations:
            print("  Recommendations:")
            for rec in recommendations:
                print(f"    → {rec}")

def main():
    parser = argparse.ArgumentParser(description='Analyze Aptos transaction performance')
    parser.add_argument('log_directory', help='Directory containing performance logs')
    parser.add_argument('--output', '-o', default='performance_analysis', 
                       help='Output directory for reports and visualizations')
    parser.add_argument('--export-json', help='Export data to JSON file')
    parser.add_argument('--no-visualizations', action='store_true', 
                       help='Skip generating visualization charts')
    
    args = parser.parse_args()
    
    # Create analyzer
    analyzer = TransactionPerformanceAnalyzer(args.log_directory)
    
    # Parse logs
    analyzer.parse_log_files()
    
    if len(analyzer.timing_records) == 0:
        print("No performance data found in logs")
        return
    
    # Generate report
    analyzer.print_report()
    
    # Create output directory
    output_dir = Path(args.output)
    output_dir.mkdir(exist_ok=True)
    
    # Generate visualizations
    if not args.no_visualizations:
        try:
            analyzer.generate_visualizations(output_dir)
        except ImportError:
            print("Warning: matplotlib/seaborn not available, skipping visualizations")
        except Exception as e:
            print(f"Warning: Failed to generate visualizations: {e}")
    
    # Export data if requested
    if args.export_json:
        analyzer.export_data(args.export_json)
    
    # Export summary to file
    with open(output_dir / 'performance_summary.txt', 'w') as f:
        original_stdout = sys.stdout
        sys.stdout = f
        analyzer.print_report()
        sys.stdout = original_stdout
    
    print(f"\n✓ Analysis completed. Results saved in: {output_dir}")

if __name__ == '__main__':
    main()
