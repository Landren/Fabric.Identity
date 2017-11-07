﻿using Fabric.Identity.API.Configuration;
using Fabric.Identity.API.Extensions;
using Fabric.Identity.API.Persistence.InMemory.Services;
using Fabric.Identity.API.Persistence.InMemory.Stores;
using Fabric.Identity.API.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Serilog;

namespace Fabric.Identity.API.Persistence.InMemory.DependencyInjection
{
    public class InMemoryIdentityServerConfigurator : BaseIdentityServerConfigurator
    {
        public InMemoryIdentityServerConfigurator(
            IIdentityServerBuilder identityServerBuilder,
            IServiceCollection serviceCollection,
            IAppConfiguration appConfiguration,
            ILogger logger)
            : base(identityServerBuilder, serviceCollection, appConfiguration, logger)
        {
        }

        protected override void ConfigureInternalStores()
        {
            ServiceCollection.TryAddSingleton<IDocumentDbService, InMemoryDocumentService>();
            ServiceCollection.AddTransient<IApiResourceStore, InMemoryApiResourceStore>();
            ServiceCollection.AddTransient<IIdentityResourceStore, InMemoryIdentityResourceStore>();
            ServiceCollection.AddTransient<IClientManagementStore, InMemoryClientManagementStore>();
            ServiceCollection.AddTransient<IUserStore, InMemoryUserStore>();
            ServiceCollection.AddTransient<IDbBootstrapper, InMemoryDbBootstrapper>();
        }

        protected override void ConfigureIdentityServer()
        {
            IdentityServerBuilder
                .AddTemporarySigningCredential()
                .AddTestUsersIfConfigured(AppConfiguration.HostingOptions)
                .AddCorsPolicyService<CorsPolicyService>()
                .AddResourceStore<InMemoryResourceStore>()
                .AddClientStore<InMemoryClientManagementStore>()
                .Services.AddTransient<IdentityServer4.Stores.IPersistedGrantStore, InMemoryPersistedGrantStore>();
        }
    }
}