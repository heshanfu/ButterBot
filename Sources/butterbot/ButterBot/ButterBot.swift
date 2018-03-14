//
//  ButterBot.swift
//  butterbot
//
//  Created by Allan Vialatte on 10/03/2018.
//

import Foundation
import SlackKit
import MySQL
import RxSwift

class ButterBot {
  let database: Database
  let slackKit: SlackKit
  var features: [ButterFeature]
  
  fileprivate let disposeBag = DisposeBag()
  fileprivate let subject = PublishSubject<ButterEvent>()
  
  init() throws {
    let env = try Environment()
    
    self.database = Database(with: env)
    self.slackKit = SlackKit()
    self.features = [Karma(),
                     IsIt()]
    slackKit.addRTMBotWithAPIToken(env.slackBotToken)
    slackKit.addWebAPIAccessWithToken(env.slackBotToken)
    self.listen(event: .message)
  }
  
  func setup() {
    let setups = self.features.compactMap { $0.setup(database: self.database) }
    Observable.from(setups).subscribe().disposed(by: self.disposeBag)
    logger.info("Butterbot Started")
  }
  
  func run() {
    logger.info("Butterbot Run ")
    self.subject
      .subscribeOn(ConcurrentDispatchQueueScheduler.init(qos: .background))
      .observeOn(ConcurrentDispatchQueueScheduler.init(qos: .background))
      .flatMap { (event) -> Observable<ButterAction> in
      guard let action: ButterAction = self.chooseBestAction(for: event) else { return Observable.empty() }
      return Observable.just(action)
      }
      .flatMap { return $0.execute() }
      .flatMap { return self.sendWebMessag(message: $0) }
      .subscribe(onNext: { (message) in
        logger.info("[Send Message] : \(message)")
      }, onError: { (error) in
        logger.error("[Error] : \(error)")
      }, onCompleted: {
        logger.warning("[Subject is completed]")
      }).disposed(by: self.disposeBag)
  }
}

extension ButterBot {
  fileprivate func chooseBestAction(for event: ButterEvent) -> ButterAction? {
    let actions = self.features.flatMap { $0.actions(for: event) }.sorted { $0.priority > $1.priority }
    return actions.filter { $0.isValid }.first
  }
}


extension ButterBot {
  fileprivate func listen(event:EventType) {
    self.slackKit.notificationForEvent(.message) { [weak self] (event, clientConnection) in
      guard let this = self, let client = clientConnection else { return }
      guard let bEvent = ButterEvent(event: event, client: client, database: this.database) else { return }
      this.subject.on(.next(bEvent))
    }
  }
}
