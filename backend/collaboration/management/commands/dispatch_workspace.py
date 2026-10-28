from datetime import date
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from collaboration.dispatch import dispatch, SLOTS, ZONE
from collaboration.models import Workspace

class Command(BaseCommand):
    help = 'Publish scheduled content only to explicitly enabled presentation workspaces.'
    def add_arguments(self, parser):
        parser.add_argument('--date', type=date.fromisoformat)
        parser.add_argument('--slot', type=int, choices=list(SLOTS))
        parser.add_argument('--workspace', type=int)
    def handle(self, *args, **options):
        now = timezone.now().astimezone(ZONE)
        day = options['date'] or now.date()
        if day > now.date():
            raise CommandError('Future publication is not allowed')
        slots = [options['slot']] if options['slot'] else list(SLOTS)
        workspaces = Workspace.objects.filter(dispatch_enabled=True)
        if options['workspace']:
            workspaces = workspaces.filter(pk=options['workspace'])
        total = 0
        for workspace in workspaces:
            for slot in slots:
                if day == now.date() and slot > now.hour:
                    continue
                total += dispatch(workspace.pk, day, slot)
        self.stdout.write(f'published={total}; workspaces={workspaces.count()}; day={day}')
