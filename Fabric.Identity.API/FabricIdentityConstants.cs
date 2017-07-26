﻿namespace Fabric.Identity.API
{
    public static class FabricIdentityConstants
    {
        public static readonly string ServiceName = "identityservice";
        public static readonly string FabricCorsPolicyName = "FabricCorsPolicy";
        public static readonly string ManagementApiBasePath = "/api";
        public static readonly string IdentityRegistrationScope = "fabric/identity.manageresources";
        public static readonly string AuditEventCategory = "Audit";

        public static class DocumentTypes
        {
            public static readonly string IdentityResourceDocumentType = "identityresource:";
            public static readonly string ClientDocumentType = "client:";
            public static readonly string ApiResourceDocumentType = "apiresource:";
            public static readonly string PersistedGrantDocumentType = "persistedgrant:";
        }

        public static class FabricClaimTypes
        {
            public static readonly string Groups = "groups";
        }

        public static class FabricCouchDbDesignDocumentDefinitions
        {
            public static readonly string Count = @"{
                                                      ""_id"":""_design/count"",
                                                      ""language"": ""javascript"",
                                                      ""views"":
                                                      {
                                                        ""client:"": {
                                                          ""map"": ""function(doc) { if (doc._id.indexOf('client:') !== -1)  emit(doc.id, 1) }"",
                                                          ""reduce"" : ""_count""
                                                        },
                                                        ""apiresource:"": {
                                                          ""map"": ""function(doc) { if (doc._id.indexOf('apiresource:') !== -1)  emit(doc.id, 1) }"",
                                                          ""reduce"" : ""_count""
                                                        },
                                                        ""identityresource:"": {
                                                          ""map"": ""function(doc) { if (doc._id.indexOf('identityresource:') !== -1)  emit(doc.id, 1) }"",
                                                          ""reduce"" : ""_count""
                                                        }
                                                      }
                                                    }";
        }

        public static class FabricCouchDbDesignDocuments
        {
            public static readonly string Count = "count";
        }

        public static class CustomEventIds
        {
            public static readonly int EntityCreatedAudit = 2000;
            public static readonly int EntityUpdatedAudit = 2001;
            public static readonly int EntityDeletedAudit = 2002;
            public static readonly int EntityReadAudit = 2003;
        }

        public static class CustomEventNames
        {
            public static readonly string EntityCreatedAudit = "EntityCreated";
            public static readonly string EntityUpdatedAudit = "EntityUpdated";
            public static readonly string EntityDeletedAudit = "EntityDeleted";
            public static readonly string EntityReadAudit = "EntityRead";
        }
    }
}