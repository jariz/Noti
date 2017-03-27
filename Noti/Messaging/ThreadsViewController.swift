//
//  ThreadsViewController.swift
//  Noti
//
//  Created by Brian Clymer on 10/22/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Cocoa

class ThreadsViewController: NSViewController {

    @IBOutlet fileprivate var tableView: NSTableView!

    private let parentVc: NSViewController?

    fileprivate let smsService: SmsService
    
    fileprivate weak var threadVc: ThreadViewController?
    
    fileprivate var threads = [ThreadPreview]() {
        didSet {
            tableView.reloadData()
        }
    }

    init(smsService: SmsService, parentVc: NSViewController?) {
        self.smsService = smsService
        self.parentVc = parentVc
        super.init(nibName: nil, bundle: nil)!

        NotificationCenter.default.addObserver(forName: Notification.Name("HackyRepository"), object: nil, queue: nil, using: { [weak self] _ in
            if let threads = SharedAppDelegate.cache.threads[smsService.device.id] {
                self?.threads = threads
            }
        })
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.window?.title = self.smsService.device.name

        tableView.register(NSNib.init(nibNamed: "ThreadTableCellView", bundle: nil), forIdentifier: "ThreadCell")

        smsService.fetchThreads { [weak self] threads in
            self?.threads = threads
        }
    }

    @IBAction func tappedBack(sender: Any?) {
        self.view.window?.contentViewController = self.parentVc
    }
    
}

extension ThreadsViewController: NSTableViewDelegate, NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return threads.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.make(withIdentifier: "ThreadCell", owner: nil) as! ThreadTableCellView
        cell.threadName.stringValue = threads[row].recipients.first?.name ?? "Unknown"
        cell.threadPreview.stringValue = threads[row].latest.body
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 58
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let thread = threads[tableView.selectedRow]
        let threadVc = ThreadViewController(thread: thread, smsService: self.smsService, parentVc: self)
        self.view.window?.contentViewController = threadVc
        self.threadVc = threadVc
    }
}
