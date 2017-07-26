﻿using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using IdentityServer4.Extensions;
using Newtonsoft.Json;

namespace Fabric.Identity.API.Services
{
    public class InMemoryDocumentService : IDocumentDbService
    {
        private static readonly ConcurrentDictionary<string, string> Documents = new ConcurrentDictionary<string, string>();

        private string GetFullDocumentId<T>(string documentId)
        {
            return $"{typeof(T).Name.ToLowerInvariant()}:{documentId}";
        }

        public Task<T> GetDocument<T>(string documentId)
        {
            string documentJson;
            return Task.FromResult(Documents.TryGetValue(GetFullDocumentId<T>(documentId), out documentJson) 
                ? JsonConvert.DeserializeObject<T>(documentJson) 
                : default(T));
        }

        public Task<IEnumerable<T>> GetDocuments<T>(string documentType)
        {
            var documentList = new List<T>();
            var documents = Documents.Where(d => d.Key.StartsWith(documentType)).Select(d => d.Value).ToList();

            foreach (var document in documents)
            {
                documentList.Add(JsonConvert.DeserializeObject<T>(document));
            }
            return Task.FromResult((IEnumerable<T>)documentList);
        }

        public Task<int> GetDocumentCount(string documentType)
        {
            var count = Documents.Count(d => d.Key.StartsWith(documentType));
            return Task.FromResult(count);
        }

        public void AddDocument<T>(string documentId, T documentObject)
        {
            var fullDocumentId = GetFullDocumentId<T>(documentId);
            if(!Documents.TryAdd(fullDocumentId, JsonConvert.SerializeObject(documentObject)))
            {
                //TODO: Use non standard exception or change to TryAddDocument.
                throw new ArgumentException($"Document with id {documentId} already exists.");
            }
        }

        public void UpdateDocument<T>(string documentId, T documentObject)
        {
            var fullDocumentId = GetFullDocumentId<T>(documentId);
            var currentValue = Documents[fullDocumentId]; //TODO: support legitimate conditional updates ?

            if (!Documents.TryUpdate(fullDocumentId, JsonConvert.SerializeObject(documentObject), currentValue))
            {
                //TODO: Use non standard exception or change to TryUpdateDocument.
                throw new ArgumentException($"Failed to update document with id {documentId}.");
            }
        }

        public void DeleteDocument<T>(string documentId)
        {
            string document;
            Documents.TryRemove(GetFullDocumentId<T>(documentId), out document);
        }
    }
}