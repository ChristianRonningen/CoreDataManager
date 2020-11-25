//
//  CoreDataManager.swift
//  OnTagScorecard
//
//  Created by Christian Rönningen on 2020-10-19.
//  Copyright © 2020 EVRY One Halmstad AB. All rights reserved.
//

import Foundation
import CoreData

public struct CoreDataManagerConfiguration {
    public init(persistentContainerName: String, migrationBlock: (() -> Void)?) {
        self.persistentContainerName = persistentContainerName
        self.migrationBlock = migrationBlock
    }
    
    fileprivate let persistentContainerName: String
    fileprivate let migrationBlock: (() -> Void)?
}

@available(OSX 10.12, *)
@objc
public class CoreDataManager: NSObject {
    
    public static var configuration: CoreDataManagerConfiguration?
    
    @objc
    public static let shared = CoreDataManager()
    private let persistentContainer: NSPersistentContainer
    private lazy var backgroundContext: NSManagedObjectContext = {
        return persistentContainer.newBackgroundContext()
    }()
    
    fileprivate override init() {
        
        assert(CoreDataManager.configuration != nil, "Set configuration before use")
        
        guard let configuration = CoreDataManager.configuration else {
            fatalError("Set configuration before use")
        }
        
        configuration.migrationBlock?()
        
        persistentContainer = NSPersistentContainer(name: configuration.persistentContainerName)
        persistentContainer.loadPersistentStores { (desc, err) in
            
        }
    }
    
    @objc
    public func performBackgroundTask(block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundContext.perform {
            block(self.backgroundContext)
        }
    }
    
    @objc
    public func performTask(block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.viewContext.performAndWait {
            block(self.persistentContainer.viewContext)
        }
    }

    @objc
    @discardableResult
    public func saveMainContext() -> Bool {
        var result = true
        performTask { (ctx) in
            do {
                try ctx.saveIfNeeded()
            } catch {
                result = false
            }
        }
        return result
    }
    
    @objc
    public func saveBackgroundContext(completion: @escaping () -> Void) {
        performBackgroundTask { (ctx) in
            do {
                try ctx.saveIfNeeded()
            } catch {}
            
            DispatchQueue.main.async(execute: completion)
        }
    }
    
    @objc
    public func performFetchRequest(request: NSFetchRequest<NSFetchRequestResult>) -> [NSManagedObject] {
        assert(Thread.current.isMainThread)
        
        var result: [NSManagedObject] = []
        performTask { (ctx) in
            do {
                result = (try ctx.fetch(request) as? [NSManagedObject]) ?? []
            } catch { }
        }
        return result
    }
    
    @nonobjc
    public func performFetchRequest<T>(request: NSFetchRequest<T>) -> [T] where T: NSManagedObject {
        assert(Thread.current.isMainThread)
        
        var result: [T] = []
        performTask { (ctx) in
            do {
                result = try ctx.fetch(request)
            } catch { }
        }
        return result
    }
    
    public func performFetchRequest<T>(request: NSFetchRequest<T>, completion: @escaping ([T]) -> Void) where T: NSManagedObject {
        
        performBackgroundTask { (ctx) in
            let result = try? ctx.fetch(request)
            
            self.performTask { (ctx) in
                
                let result: [T] = result?.compactMap({ object in
                    if let id = (object as? NSManagedObject)?.objectID {
                        return ctx.object(with: id) as? T
                    } else {
                        return nil
                    }
                }) ?? []
                
                completion(result)
            }
            
        }
    }
    
    @objc
    public func fetchOrInsertNew(of type: NSEntityDescription, fetchRequest: NSFetchRequest<NSFetchRequestResult>, values: [String: Any]) -> NSManagedObject? {
        var value = performFetchRequest(request: fetchRequest).first
        if value == nil {
            value = insertNew(of: type, values: values)
        } else {
            value = update(object: value!, values: values)
        }
        return value
    }
    
    @nonobjc
    public func fetchOrInsertNew<T>(of type: T.Type, fetchRequest: NSFetchRequest<T>, values: [String: Any]) -> T? where T: NSManagedObject {
        var value = performFetchRequest(request: fetchRequest).first
        if value == nil {
            value = insertNew(of: type, values: values)
        } else {
            value = update(object: value!, values: values)
        }
        return value
    }

    @objc
    public func insertNew(of type: NSEntityDescription, values: [String: Any]) -> NSManagedObject? {
        assert(Thread.isMainThread)
        
        var newObject: NSManagedObject?
        CoreDataManager.shared.performTask { (ctx) in
            let insertedObject = NSEntityDescription.insertNewObject(forEntityName: type.name!, into: ctx)
            for value in values {
                insertedObject.setValue(value.value, forKey: value.key)
            }
            
            do {
                _ = try ctx.saveIfNeeded()
                newObject = insertedObject
            } catch {
                print(error)
            }
        }
        return newObject
    }
    
    @nonobjc
    public func insertNew<T>(of type: T.Type, values: [String: Any]) -> T? where T: NSManagedObject {
        assert(Thread.isMainThread)
        
        var newObject: T?
        CoreDataManager.shared.performTask { (ctx) in
            let insertedObject = NSEntityDescription.insertNewObject(forEntityName: type.entity().name!, into: ctx) as? T
            for value in values {
                insertedObject?.setValue(value.value, forKey: value.key)
            }
            
            do {
                _ = try ctx.saveIfNeeded()
                newObject = insertedObject
            } catch {
                print(error)
            }
        }
        return newObject
    }
    
    ///
    @objc
    @discardableResult
    public func update(object: NSManagedObject, values: [String: Any]) -> NSManagedObject {
        for (key, value) in values {
            object.setValue(value, forKey: key)
        }
        
        do {
            try object.managedObjectContext?.saveIfNeeded()
        } catch {}
        
        return object
    }
    
    @discardableResult
    @nonobjc
    public func update<T>(object: T, values: [String: Any]) -> T where T: NSManagedObject {
        
        for (key, value) in values {
            object.setValue(value, forKey: key)
        }
        
        do {
            try object.managedObjectContext?.saveIfNeeded()
        } catch {}
        
        return object
    }
    
    /// Background context
    @nonobjc
    public func insertNew<T>(of type: T.Type, values: [[String: Any]], completion: @escaping (([T]) -> Void)) where T: NSManagedObject {
        CoreDataManager.shared.performBackgroundTask { (ctx) in
            var objects = [NSManagedObject]()
            for value in values {
                let insertedObject = NSEntityDescription.insertNewObject(forEntityName: type.entity().name!, into: ctx)
                for (key, value) in value {
                    insertedObject.setValue(value, forKey: key)
                }
                objects.append(insertedObject)
            }
            
            do {
                _ = try ctx.saveIfNeeded()
                CoreDataManager.shared.performTask { (ctx) in
                    let objs = objects.compactMap({ obj in
                        return ctx.object(with: obj.objectID) as? T
                    })
                    completion(objs)
                }
            } catch {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    @objc(deleteObjects:)
    public func delete(objects: [NSManagedObject]) {
        performTask { (ctx) in
            for object in objects {
                ctx.delete(object)
            }
            do {
                try ctx.saveIfNeeded()
            } catch {}
        }
    }
    
    @objc(deleteObjects:completion:)
    public func delete(objects: [NSManagedObject], completion: @escaping () -> Void) {
        performBackgroundTask { (ctx) in
            for object in objects {
                ctx.delete(object)
            }
            do {
                try ctx.saveIfNeeded()
            } catch {}
            
            DispatchQueue.main.async(execute: completion)
        }
    }
    
    @nonobjc
    public func deleteFetchRequest<T>(request: NSFetchRequest<T>) where T: NSManagedObject {
        request.returnsObjectsAsFaults = true
        let objects = CoreDataManager.shared.performFetchRequest(request: request) as [T]
        performTask { (ctx) in
            do {
                for object in objects {
                    ctx.delete(object)
                }
                try ctx.saveIfNeeded()
            } catch { }
        }
    }
    
    /// Deletes all objects of type on background context
    @nonobjc
    public func deleteAll<T>(of type: T.Type, completion: @escaping (Int) -> Void) where T: NSManagedObject {
        let request = type.fetchRequest()
        deleteFetchRequest(request: request, completion: completion)
    }
    
    /// Deletes all objects from request on background context
    public func deleteFetchRequest(request: NSFetchRequest<NSFetchRequestResult>, completion: @escaping (Int) -> Void) {
        performBackgroundTask { (ctx) in
            request.returnsObjectsAsFaults = true
            var totalDeleted = 0
            do {
                let fetched = try ctx.fetch(request) as? [NSManagedObject] ?? []
                for object in fetched {
                    ctx.delete(object)
                    totalDeleted += 1
                }
                try ctx.saveIfNeeded()
            } catch {
                totalDeleted = 0
            }
            
            DispatchQueue.main.async {
                completion(totalDeleted)
            }
        }
    }

    public func controller<T>(fetchRequest: NSFetchRequest<T>, sectionNameKeyPath: String?, cacheName: String?) -> NSFetchedResultsController<T> where T: NSFetchRequestResult {
        return NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: persistentContainer.viewContext, sectionNameKeyPath: sectionNameKeyPath, cacheName: cacheName)
    }
    
    @objc
    public func controller(fetchRequest: NSFetchRequest<NSFetchRequestResult>, sectionNameKeyPath: String?, cacheName: String?) -> NSFetchedResultsController<NSFetchRequestResult> {
        return NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: persistentContainer.viewContext, sectionNameKeyPath: sectionNameKeyPath, cacheName: cacheName)
    }
}

extension NSManagedObjectContext {
    @discardableResult
    public func saveIfNeeded() throws -> Bool {
        if hasChanges {
            try save()
            return true
        }
        return false
    }
    
    @objc
    @discardableResult
    public func saveIfNeededObjc() -> Bool {
        if hasChanges {
            do {
                try saveIfNeeded()
            } catch {
                return false
            }
            return true
        } else {
            return false
        }
    }
}
